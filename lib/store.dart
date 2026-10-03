import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'domain.dart';
import 'planning.dart';
import 'recurrence.dart';
import 'platform_bridge.dart';
import 'record_sync.dart';

class GritStore extends ChangeNotifier {
  List<Task> tasks = [];
  List<GritEvent> events = [];
  Set<String> freezes = {};
  List<Project> projects = [];
  List<String> customCategories = [];
  List<SavedFilter> filters = [];
  List<Map<String, dynamic>> activity = [];
  bool darkMode = false;
  String appearance = 'System';
  bool oledBlack = false;
  bool gamification = false;
  String density = 'Comfortable';
  double get taskPadding =>
      {'Compact': 9.0, 'Comfortable': 16.0, 'Spacious': 23.0}[density] ?? 16;
  bool previewMode = false;
  int dailyGoal = 5;
  int weeklyGoal = 25;
  String? _undo;
  int _undoRevision = 0;
  int get undoRevision => _undoRevision;
  String? freezeWeek;
  int _idCounter = 0;
  String id() => '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';
  Iterable<Task> get activeTasks => tasks
      .where((t) => !t.trashed && !(project(t.projectId)?.archived ?? false));
  Project? project(String? id) {
    for (final p in projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  String projectName(Task t) => project(t.projectId)?.name ?? 'Inbox';
  bool isProjectDescendant(String candidate, String ancestor) {
    final seen = <String>{};
    var p = project(candidate);
    while (p?.parentId != null && seen.add(p!.id)) {
      if (p.parentId == ancestor) return true;
      p = project(p.parentId);
    }
    return false;
  }

  List<Project> projectTree([String? parent]) {
    final siblings = projects
        .where((p) => p.parentId == parent && !p.archived)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return [
      for (final p in siblings) ...[p, ...projectTree(p.id)]
    ];
  }

  int projectDepth(Project p) {
    var depth = 0;
    final seen = <String>{};
    while (p.parentId != null && seen.add(p.id)) {
      final parent = project(p.parentId);
      if (parent == null) break;
      depth++;
      p = parent;
    }
    return depth;
  }

  void reparentProject(Project p, String? parent) {
    if (parent == p.id ||
        (parent != null && isProjectDescendant(parent, p.id))) {
      throw const FormatException('A project cannot be nested inside itself.');
    }
    checkpoint();
    p.parentId = parent;
    p.order = projects.where((x) => x.parentId == parent).length;
    save();
  }

  void reorderProject(Project source, Project target) {
    if (source.id == target.id) return;
    if (target.parentId == source.id ||
        (target.parentId != null &&
            isProjectDescendant(target.parentId!, source.id))) {
      return;
    }
    checkpoint();
    source.parentId = target.parentId;
    final siblings = projects
        .where((p) => p.parentId == target.parentId && p.id != source.id)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    siblings.insert(siblings.indexOf(target), source);
    for (var i = 0; i < siblings.length; i++) {
      siblings[i].order = i;
    }
    save();
  }

  void timeBlock(Task t, DateTime start) {
    final end = start.add(Duration(minutes: t.minutes));
    if (tasks.any((x) =>
        x.id != t.id &&
        !x.trashed &&
        !x.done(DateTime.now()) &&
        x.blockStart != null &&
        start.isBefore(x.blockStart!.add(Duration(minutes: x.minutes))) &&
        end.isAfter(x.blockStart!))) {
      throw const FormatException(
          'This block overlaps another task. Choose a different time.');
    }
    checkpoint();
    t.blockStart = start;
    t.scheduled = start;
    t.snoozedUntil = null;
    record('Time blocked', t.title);
    save();
  }

  int get goalStreak {
    var current = day(DateTime.now());
    if (completedOn(current) < dailyGoal) {
      current = current.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (streak < 36500 && completedOn(current) >= dailyGoal) {
      streak++;
      current = DateTime(current.year, current.month, current.day - 1);
    }
    return streak;
  }

  List<Task> descendants(String parentId) {
    final found = <Task>[];
    final seen = <String>{parentId};
    final queue = <String>[parentId];
    while (queue.isNotEmpty) {
      final parent = queue.removeLast();
      for (final child in tasks.where((t) => t.parentId == parent)) {
        if (seen.add(child.id)) {
          found.add(child);
          queue.add(child.id);
        }
      }
    }
    return found;
  }

  void checkpoint() {
    _undo = jsonEncode(toJson());
    _undoRevision++;
  }

  int focusElapsed(Task task, [DateTime? at]) {
    final target = task.minutes.clamp(1, 25) * 60000;
    final delta = task.focusStartedAt == null
        ? 0
        : (at ?? DateTime.now())
            .difference(task.focusStartedAt!)
            .inMilliseconds;
    return (task.focusMilliseconds + (delta < 0 ? 0 : delta)).clamp(0, target);
  }

  void startFocus(Task task, {DateTime? at}) {
    // Only one timer runs at a time; starting another pauses the previous one.
    for (final other
        in tasks.where((t) => t.id != task.id && t.focusStartedAt != null)) {
      pauseFocus(other, at: at);
    }
    task.focusSessionId ??= id();
    task.focusStartedAt ??= at ?? DateTime.now();
    save();
  }

  void pauseFocus(Task task, {DateTime? at}) {
    task.focusMilliseconds = focusElapsed(task, at);
    task.focusStartedAt = null;
    save();
  }

  void finishFocus(Task task, {DateTime? at}) {
    final seconds = focusElapsed(task, at) ~/ 1000;
    if (seconds > 0 &&
        task.focusSessionId != null &&
        !task.focusLogs.any((l) => l['id'] == task.focusSessionId)) {
      task.focusLogs = [
        ...task.focusLogs,
        {
          'id': task.focusSessionId,
          'seconds': seconds,
          'endedAt': (at ?? DateTime.now()).toIso8601String()
        }
      ];
    }
    task.focusMilliseconds = 0;
    task.focusStartedAt = null;
    task.focusSessionId = null;
    save();
  }

  bool undo({int? expectedRevision}) {
    if (_undo == null ||
        (expectedRevision != null && expectedRevision != _undoRevision)) {
      return false;
    }
    final raw = _undo!;
    _undo = null;
    _undoRevision++;
    _decode(jsonDecode(raw));
    save();
    return true;
  }

  void record(String verb, String title) {
    activity.insert(0,
        {'verb': verb, 'title': title, 'at': DateTime.now().toIso8601String()});
    if (activity.length > 500) activity.removeLast();
  }

  void addTask(Task t) {
    checkpoint();
    tasks.add(t);
    record('Added', t.title);
    save();
  }

  void deleteTask(Task t) {
    checkpoint();
    t.trashed = true;
    for (final child in descendants(t.id)) {
      child.trashed = true;
    }
    record('Moved to trash', t.title);
    save();
  }

  void restoreTask(Task t) {
    t.trashed = false;
    for (final child in descendants(t.id)) {
      child.trashed = false;
    }
    record('Restored', t.title);
    save();
  }

  void duplicate(Task t) {
    checkpoint();
    final children = descendants(t.id).where((x) => !x.trashed).toList();
    final copy = Task.fromJson({
      ...t.toJson(),
      'id': id(),
      'doneAt': null,
      'history': <String>[],
      'focusLogs': <dynamic>[],
      'focusStartedAt': null,
      'focusMilliseconds': 0,
      'focusSessionId': null,
      'comments': <dynamic>[]
    });
    copy.title = '${t.title} (copy)';
    tasks.add(copy);
    final copiedIds = <String, String>{t.id: copy.id};
    for (final sub in children) {
      copiedIds[sub.id] = id();
    }
    for (final sub in children) {
      tasks.add(Task.fromJson({
        ...sub.toJson(),
        'id': copiedIds[sub.id],
        'parentId': copiedIds[sub.parentId],
        'doneAt': null,
        'history': <String>[],
        'focusLogs': <dynamic>[],
        'focusStartedAt': null,
        'focusMilliseconds': 0,
        'focusSessionId': null,
        'comments': <dynamic>[]
      }));
    }
    record('Duplicated', t.title);
    save();
  }

  void schedule(Task t, DateTime? date) {
    checkpoint();
    t.scheduled = date;
    t.blockStart = null;
    t.snoozedUntil = null;
    record('Rescheduled', t.title);
    save();
  }

  void completeMany(Set<String> ids) {
    final before = jsonEncode(toJson());
    for (final t in tasks.where((t) => ids.contains(t.id)).toList()) {
      if (!t.done(DateTime.now())) toggle(t);
    }
    _undo = before;
    _undoRevision++;
  }

  void move(Task t, String? projectId, String section) {
    checkpoint();
    t.projectId = projectId;
    t.section = section;
    for (final child in descendants(t.id)) {
      child.projectId = projectId;
      child.section = section;
    }
    record('Moved', t.title);
    save();
  }

  void addProject(Project p) {
    checkpoint();
    projects.add(p);
    record('Created project', p.name);
    save();
  }

  bool addCustomCategory(String raw) {
    final value = raw.trim();
    if (value.isEmpty ||
        Category.values
            .any((c) => c.label.toLowerCase() == value.toLowerCase()) ||
        customCategories.any((c) => c.toLowerCase() == value.toLowerCase())) {
      return false;
    }
    checkpoint();
    customCategories = [...customCategories, value];
    save();
    return true;
  }

  bool renameCustomCategory(String oldName, String raw) {
    final value = raw.trim();
    if (value.isEmpty ||
        Category.values
            .any((c) => c.label.toLowerCase() == value.toLowerCase()) ||
        customCategories.any(
            (c) => c != oldName && c.toLowerCase() == value.toLowerCase())) {
      return false;
    }
    checkpoint();
    customCategories =
        customCategories.map((c) => c == oldName ? value : c).toList();
    for (final task in tasks.where((t) => t.customCategory == oldName)) {
      task.customCategory = value;
    }
    save();
    return true;
  }

  void removeCustomCategory(String name) {
    checkpoint();
    customCategories = customCategories.where((c) => c != name).toList();
    for (final task in tasks.where((t) => t.customCategory == name)) {
      task.customCategory = '';
      task.category = Category.personalProject;
    }
    save();
  }

  void addComment(Task t, String text) {
    t.comments = List.of(t.comments)
      ..add({
        'text': text,
        'author': name,
        'at': DateTime.now().toIso8601String()
      });
    record('Commented on', t.title);
    save();
  }

  void importBackup(String raw) {
    final j = jsonDecode(raw);
    if (j is! Map<String, dynamic> || j['tasks'] is! List) {
      throw const FormatException('Choose a GRIT JSON backup.');
    }
    final parsed = (j['tasks'] as List)
        .map((e) => Task.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    if (parsed.any((t) =>
        t.minutes < 1 ||
        t.importance < 1 ||
        t.importance > 5 ||
        t.priority < 1 ||
        t.priority > 4)) {
      throw const FormatException('This backup has invalid task values.');
    }
    final staged = GritStore();
    staged._decode(j);
    for (final p in staged.projects) {
      final seen = <String>{p.id};
      var parent = p.parentId;
      while (parent != null) {
        if (!seen.add(parent)) {
          throw const FormatException('Project hierarchy contains a cycle.');
        }
        final node = staged.project(parent);
        if (node == null) {
          throw const FormatException('Project parent is missing.');
        }
        parent = node.parentId;
      }
    }
    for (final t in staged.tasks) {
      if (t.recurrence.isNotEmpty) RecurrenceRule.parse(t.recurrence);
      if (t.fields.map((f) => f.name.trim().toLowerCase()).toSet().length !=
              t.fields.length ||
          t.focusMilliseconds < 0 ||
          t.focusMilliseconds > 1500000) {
        throw const FormatException('Invalid custom fields or focus session.');
      }
    }
    if (staged.capacity < 30 ||
        staged.capacity > 480 ||
        staged.dailyGoal < 1 ||
        staged.dailyGoal > 30 ||
        staged.weeklyGoal < 1 ||
        staged.weeklyGoal > 210 ||
        staged.tasks.map((t) => t.id).toSet().length != staged.tasks.length) {
      throw const FormatException(
          'This backup has invalid settings or duplicate tasks.');
    }
    for (final f in staged.filters) {
      TaskQuery.matches(
          Task(id: 'validate', title: ''), f.query, DateTime.now());
    }
    checkpoint();
    _decode(j);
    record('Restored', 'Planner backup');
    save();
  }

  String name = 'Student', error = '';
  int capacity = 240;
  bool onboarded = false, cloud = false, loading = false;
  SharedPreferences? prefs;
  StreamSubscription? subscription;
  RecordSync? recordSync;
  Map<String, Map<String, dynamic>> _syncBaseline = {};
  User? get user => cloud ? FirebaseAuth.instance.currentUser : null;
  String get cacheKey => 'grit.v1.${user?.uid ?? 'local'}';
  final engine = const PriorityEngine();
  int _completions(Task t, DateTime date) =>
      t.category == Category.habit || t.recurrence.isNotEmpty
          ? t.history.where((h) => h.startsWith(dayKey(date))).length
          : t.doneAt != null && dayKey(t.doneAt!) == dayKey(date)
              ? 1
              : 0;
  int get completedMinutesToday => tasks.where((t) => t.parentId == null).fold(
      0, (total, t) => total + _completions(t, DateTime.now()) * t.minutes);
  int get remainingCapacity =>
      (capacity - completedMinutesToday).clamp(0, capacity);
  Future<void> init({bool enableCloud = true}) async {
    prefs = await SharedPreferences.getInstance();
    if (enableCloud && const bool.fromEnvironment('FIREBASE_ENABLED')) {
      try {
        await Firebase.initializeApp(
            options: const FirebaseOptions(
                apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
                appId: String.fromEnvironment('FIREBASE_APP_ID'),
                messagingSenderId: String.fromEnvironment('FIREBASE_SENDER_ID'),
                projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
                authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN')));
        cloud = true;
        FirebaseFirestore.instance.settings =
            const Settings(persistenceEnabled: true);
      } catch (e) {
        error = 'Cloud setup is incomplete. Your local planner still works.';
      }
    }
    _restore();
    await consumeWidgetCompletions();
    unawaited(updateTodayWidget(activeTasks, workspace: cacheKey));
    if (user != null) _listen();
  }

  void _restore() {
    // Undo snapshots must never cross account/workspace boundaries.
    _undo = null;
    _undoRevision++;
    _syncBaseline = {};
    tasks = [];
    events = [];
    freezes = {};
    projects = [];
    customCategories = [];
    filters = [];
    activity = [];
    darkMode = false;
    appearance = 'System';
    oledBlack = false;
    gamification = false;
    density = 'Comfortable';
    dailyGoal = 5;
    weeklyGoal = 25;
    freezeWeek = null;
    name = 'Student';
    capacity = 240;
    onboarded = false;
    final raw = prefs?.getString(cacheKey);
    if (raw != null) {
      try {
        _decode(jsonDecode(raw));
      } catch (e) {
        error = 'Saved data could not be read. It has not been overwritten.';
      }
    }
  }

  void _decode(Map<String, dynamic> j) {
    tasks = (j['tasks'] as List? ?? [])
        .map((e) => Task.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    events = (j['events'] as List? ?? [])
        .map((e) => GritEvent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    name = j['name'] ?? 'Student';
    capacity = j['capacity'] ?? 240;
    onboarded = j['onboarded'] ?? false;
    freezes = Set<String>.from(j['freezes'] ?? []);
    projects = (j['projects'] as List? ?? [])
        .map((p) => Project.fromJson(Map<String, dynamic>.from(p)))
        .toList();
    customCategories = (j['customCategories'] as List? ?? [])
        .map((c) => c.toString().trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
    for (final custom in tasks
        .map((t) => t.customCategory.trim())
        .where((c) => c.isNotEmpty)) {
      if (!customCategories.contains(custom)) customCategories.add(custom);
    }
    filters = (j['filters'] as List? ?? [])
        .map((p) => SavedFilter.fromJson(Map<String, dynamic>.from(p)))
        .toList();
    activity = (j['activity'] as List? ?? [])
        .map((p) => Map<String, dynamic>.from(p))
        .toList();
    darkMode = j['darkMode'] ?? false;
    appearance = ['System', 'Light', 'Dark'].contains(j['appearance'])
        ? j['appearance']
        : j.containsKey('darkMode')
            ? (darkMode ? 'Dark' : 'Light')
            : 'System';
    oledBlack = j['oledBlack'] == true;
    gamification = j['gamification'] == true;
    density = ['Compact', 'Comfortable', 'Spacious'].contains(j['density'])
        ? j['density']
        : 'Comfortable';
    dailyGoal = j['dailyGoal'] ?? 5;
    weeklyGoal = j['weeklyGoal'] ?? 25;
    freezeWeek = j['freezeWeek'];
    // Migrate v1 course labels into real projects without changing user tasks.
    if (j['projects'] == null) {
      for (final course
          in tasks.map((t) => t.course).where((c) => c.isNotEmpty).toSet()) {
        final p = Project(id: 'migrated-${projects.length}', name: course);
        projects.add(p);
        for (final t in tasks.where((t) => t.course == course)) {
          t.projectId = p.id;
        }
      }
      for (final t in tasks) {
        t.scheduled ??= t.deadline;
      }
    }
  }

  Map<String, dynamic> toJson() => {
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'events': events.map((e) => e.toJson()).toList(),
        'name': name,
        'capacity': capacity,
        'onboarded': onboarded,
        'freezes': freezes.toList(),
        'projects': projects.map((p) => p.toJson()).toList(),
        'customCategories': customCategories,
        'filters': filters.map((p) => p.toJson()).toList(),
        'activity': activity,
        'darkMode': darkMode,
        'appearance': appearance,
        'oledBlack': oledBlack,
        'gamification': gamification,
        'density': density,
        'dailyGoal': dailyGoal,
        'weeklyGoal': weeklyGoal,
        'freezeWeek': freezeWeek
      };
  void _listen() {
    unawaited(recordSync?.close());
    final uid = user!.uid;
    _syncBaseline = workspaceRecords(toJson());
    recordSync = RecordSync(
        uid: uid,
        prefs: prefs,
        status: (message) {
          if (user?.uid == uid) {
            error = message;
            notifyListeners();
          }
        },
        receive: (record) {
          if (user?.uid != uid) return;
          final type = record['type'], id = record['id'];
          if (!['tasks', 'projects', 'events', 'filters', 'settings']
              .contains(type)) {
            return;
          }
          final workspace = toJson();
          if (type == 'settings') {
            workspace.addAll(Map<String, dynamic>.from(record['data']));
          } else {
            final list = List<Map<String, dynamic>>.from(workspace[type]);
            final old = list.where((item) => item['id'] == id).firstOrNull;
            list.removeWhere((item) => item['id'] == id);
            if (record['deleted'] != true) {
              final value = Map<String, dynamic>.from(record['data']);
              if (type == 'tasks') {
                value['attachments'] = old?['attachments'] ?? [];
              }
              list.add(value);
            }
            workspace[type] = list;
          }
          try {
            final staged = GritStore().._decode(workspace);
            _undo = null;
            _undoRevision++;
            _decode(staged.toJson());
            _syncBaseline = workspaceRecords(toJson());
            prefs?.setString(cacheKey, jsonEncode(toJson()));
            notifyListeners();
          } catch (e) {
            error = 'A cloud record could not be read. Local data was kept.';
          }
        });
    unawaited(recordSync!.start());
  }

  Future<void> save() async {
    _undoRevision++;
    notifyListeners();
    try {
      await prefs?.setString(cacheKey, jsonEncode(toJson()));
    } catch (e) {
      error =
          'Device storage is full. Export a backup or remove large attachments before closing the app.';
      notifyListeners();
      return;
    }
    unawaited(updateTodayWidget(activeTasks, workspace: cacheKey));
    if (user != null && recordSync != null) {
      final records = workspaceRecords(toJson()),
          changes = <String, Map<String, dynamic>>{};
      for (final entry in records.entries) {
        if (jsonEncode(entry.value) != jsonEncode(_syncBaseline[entry.key])) {
          changes[entry.key] = entry.value;
        }
      }
      for (final entry in _syncBaseline.entries) {
        if (!records.containsKey(entry.key)) {
          changes[entry.key] = {...entry.value, 'deleted': true};
        }
      }
      _syncBaseline = records;
      if (changes.isNotEmpty) await recordSync!.enqueue(changes);
    }
  }

  Future<void> authenticate(String email, String password,
      {bool register = false}) async {
    if (!cloud) throw StateError('Connect your Firebase project first.');
    if (register) {
      await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);
    } else {
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
    }
    _restore();
    _listen();
    await consumeWidgetCompletions();
    notifyListeners();
  }

  Future<void> google() async {
    if (!cloud) throw StateError('Connect your Firebase project first.');
    final p = GoogleAuthProvider();
    if (kIsWeb) {
      await FirebaseAuth.instance.signInWithPopup(p);
    } else {
      await FirebaseAuth.instance.signInWithProvider(p);
    }
    _restore();
    _listen();
    await consumeWidgetCompletions();
    notifyListeners();
  }

  Future<void> logout() async {
    await recordSync?.close();
    recordSync = null;
    await subscription?.cancel();
    await FirebaseAuth.instance.signOut();
    _restore();
    await consumeWidgetCompletions();
    notifyListeners();
  }

  Future<void> endAllSessions() async {
    if (!RecordSync.enabled) {
      throw StateError('Secure backend deployment is required first.');
    }
    await FirebaseFunctions.instanceFor(region: 'asia-south1')
        .httpsCallable('revokeAllSessions')
        .call();
    await logout();
  }

  void toggle(Task t, {DateTime? at}) {
    checkpoint();
    if (t.focusSessionId != null) finishFocus(t);
    final now = at ?? DateTime.now();
    if (t.recurrence.isNotEmpty &&
        (t.category != Category.habit || t.recurrence != 'daily')) {
      t.history = List.of(t.history)
        ..add(
            t.category == Category.habit ? dayKey(now) : now.toIso8601String());
      t.scheduled = nextTaskOccurrence(t, now);
      t.doneAt = t.scheduled == null ? now : null;
      t.blockStart = null;
      for (final child in descendants(t.id)) {
        child.doneAt = null;
      }
      record('Completed occurrence', t.title);
      save();
      return;
    }
    if (t.category == Category.habit) {
      final key = dayKey(now);
      t.history = List.of(t.history);
      t.history.contains(key) ? t.history.remove(key) : t.history.add(key);
    } else {
      t.doneAt = t.doneAt == null ? now : null;
      for (final child in descendants(t.id).where((c) => !c.trashed)) {
        child.doneAt = t.doneAt;
      }
    }
    record(t.done(now) ? 'Completed' : 'Reopened', t.title);
    save();
  }

  bool _readingWidget = false;

  /// Persist before acknowledging: replay after a crash cannot undo completion.
  Future<void> consumeWidgetCompletions() async {
    if (!hasWidgetBridge || _readingWidget || prefs == null) return;
    _readingWidget = true;
    try {
      final acknowledgements = <String>[];
      for (final e in await readWidgetCompletions()) {
        if (e['workspace'] != cacheKey || e['id'] is! String) continue;
        final t = tasks.where((t) => t.id == e['taskId']).firstOrNull;
        final at = DateTime.tryParse(e['at']?.toString() ?? '')?.toLocal();
        if (t != null &&
            !t.trashed &&
            at != null &&
            !t.done(at) &&
            t.scheduled?.toIso8601String() == e['scheduled']) {
          toggle(t, at: at);
        }
        acknowledgements.add(e['id'] as String);
      }
      if (acknowledgements.isNotEmpty) {
        final stored = await prefs!.setString(cacheKey, jsonEncode(toJson()));
        if (stored) await acknowledgeWidgetCompletions(acknowledgements);
      }
      await updateTodayWidget(activeTasks, workspace: cacheKey);
    } on PlatformException catch (_) {
      // Keep the durable queue for the next foreground reconciliation.
    } on MissingPluginException catch (_) {
    } finally {
      _readingWidget = false;
    }
  }

  void snooze(Task t) {
    t.snoozedUntil = day(DateTime.now()).add(const Duration(days: 1));
    t.pinnedDay = null;
    save();
  }

  void pin(Task t) {
    t.pinnedDay =
        t.pinnedDay == dayKey(DateTime.now()) ? null : dayKey(DateTime.now());
    t.snoozedUntil = null;
    save();
  }

  int get xp => tasks.fold(
      0,
      (total, t) =>
          total +
          (t.category == Category.habit || t.recurrence.isNotEmpty
              ? t.history.length * taskXp(t)
              : t.doneAt != null
                  ? taskXp(t)
                  : 0));
  int completedOn(DateTime d) => tasks
      .where((t) => t.parentId == null)
      .fold(0, (total, t) => total + _completions(t, d));
  bool freezeYesterday() {
    final yesterday = day(DateTime.now()).subtract(const Duration(days: 1));
    final start = day(DateTime.now())
        .subtract(Duration(days: DateTime.now().weekday - 1));
    final useWeek = dayKey(start);
    if (freezeWeek == useWeek ||
        prefs?.getString('$cacheKey.freezeWeek') == useWeek) {
      return false;
    }
    freezeWeek = useWeek;
    prefs?.setString('$cacheKey.freezeWeek', useWeek);
    freezes.add(dayKey(yesterday));
    save();
    return true;
  }

  void demo() {
    final n = DateTime.now();
    tasks = [
      Task(
          id: 'dbms',
          title: 'Finish the DBMS assignment',
          category: Category.assignment,
          course: 'Database systems',
          importance: 5,
          minutes: 60,
          deadline: n.add(const Duration(hours: 8))),
      Task(
          id: 'dsa',
          title: 'Solve 2 graph problems',
          category: Category.habit,
          course: 'Placement prep',
          importance: 3,
          minutes: 25,
          history: List.generate(
              6, (i) => dayKey(n.subtract(Duration(days: i + 1))))),
      Task(
          id: 'portfolio',
          title: 'Build the portfolio landing page',
          category: Category.personalProject,
          importance: 4,
          minutes: 50,
          deadline: n.add(const Duration(days: 4))),
      Task(
          id: 'notes',
          title: 'Revise normalization notes',
          category: Category.classWork,
          course: 'Database systems',
          importance: 4,
          minutes: 30,
          deadline: n.add(const Duration(days: 2))),
      Task(
          id: 'read',
          title: 'Read 10 pages',
          category: Category.habit,
          importance: 2,
          minutes: 15),
      Task(
          id: 'exam',
          title: 'Practice last year’s questions',
          category: Category.event,
          importance: 5,
          minutes: 60,
          deadline: n.add(const Duration(days: 6)),
          eventId: 'midterms')
    ];
    events = [
      GritEvent('midterms', 'Database systems midterm', 'Exam',
          n.add(const Duration(days: 7))),
      GritEvent('hack', 'Build something that matters', 'Hackathon',
          n.add(const Duration(days: 14)))
    ];
    onboarded = true;
    save();
  }
}
