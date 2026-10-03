import 'dart:math';

enum Category { assignment, classWork, personalProject, habit, event }

extension CategoryLabel on Category {
  String get label =>
      ['Assignment', 'Class work', 'Project', 'Habit', 'Exam / event'][index];
}

String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);

class Task {
  Task(
      {required this.id,
      required this.title,
      this.notes = '',
      this.category = Category.assignment,
      this.customCategory = '',
      this.importance = 3,
      this.minutes = 30,
      this.deadline,
      this.doneAt,
      this.snoozedUntil,
      this.pinnedDay,
      this.eventId,
      this.course = '',
      this.history = const [],
      this.projectId,
      this.section = '',
      this.parentId,
      this.labels = const [],
      this.priority = 4,
      this.scheduled,
      this.recurrence = '',
      this.recurrenceAnchor,
      this.blockStart,
      this.attachments = const [],
      this.fields = const [],
      this.focusLogs = const [],
      this.focusStartedAt,
      this.focusMilliseconds = 0,
      this.focusSessionId,
      this.comments = const [],
      this.reminder,
      this.trashed = false,
      this.order = 0});
  final String id;
  String title, notes, course;
  Category category;
  String customCategory;
  int importance, minutes, order;
  DateTime? deadline, doneAt, snoozedUntil;
  String? pinnedDay, eventId;
  List<String> history;
  String? projectId, parentId;
  String section, recurrence;
  DateTime? recurrenceAnchor, blockStart;
  List<Map<String, dynamic>> attachments;
  List<TaskField> fields;
  List<Map<String, dynamic>> focusLogs;
  DateTime? focusStartedAt;
  int focusMilliseconds;
  String? focusSessionId;
  int get actualSeconds =>
      focusLogs.fold(0, (sum, log) => sum + (log['seconds'] as int));
  List<String> labels;
  int priority;
  DateTime? scheduled, reminder;
  List<Map<String, dynamic>> comments;
  bool trashed;
  String get categoryLabel =>
      customCategory.trim().isEmpty ? category.label : customCategory;
  bool done(DateTime now) => category == Category.habit
      ? doneAt != null || history.contains(dayKey(now))
      : doneAt != null;
  bool overdue(DateTime now) =>
      !done(now) && deadline != null && deadline!.isBefore(now);
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'notes': notes,
        'category': category.name,
        'customCategory': customCategory,
        'importance': importance,
        'minutes': minutes,
        'deadline': deadline?.toIso8601String(),
        'doneAt': doneAt?.toIso8601String(),
        'snoozedUntil': snoozedUntil?.toIso8601String(),
        'pinnedDay': pinnedDay,
        'eventId': eventId,
        'course': course,
        'history': history,
        'order': order,
        'projectId': projectId,
        'section': section,
        'parentId': parentId,
        'labels': labels,
        'priority': priority,
        'scheduled': scheduled?.toIso8601String(),
        'recurrence': recurrence,
        'recurrenceAnchor': recurrenceAnchor?.toIso8601String(),
        'blockStart': blockStart?.toIso8601String(),
        'attachments': attachments,
        'fields': fields.map((f) => f.toJson()).toList(),
        'focusLogs': focusLogs,
        'focusStartedAt': focusStartedAt?.toIso8601String(),
        'focusMilliseconds': focusMilliseconds,
        'focusSessionId': focusSessionId,
        'comments': comments,
        'reminder': reminder?.toIso8601String(),
        'trashed': trashed
      };
  factory Task.fromJson(Map<String, dynamic> j) => Task(
      id: j['id'],
      title: j['title'],
      notes: j['notes'] ?? '',
      category: Category.values.firstWhere((c) => c.name == j['category'],
          orElse: () => Category.assignment),
      customCategory: j['customCategory'] ?? '',
      importance: j['importance'] ?? 3,
      minutes: j['minutes'] ?? 30,
      deadline: DateTime.tryParse(j['deadline'] ?? ''),
      doneAt: DateTime.tryParse(j['doneAt'] ?? ''),
      snoozedUntil: DateTime.tryParse(j['snoozedUntil'] ?? ''),
      pinnedDay: j['pinnedDay'],
      eventId: j['eventId'],
      course: j['course'] ?? '',
      history: List<String>.from(j['history'] ?? []),
      projectId: j['projectId'],
      section: j['section'] ?? '',
      parentId: j['parentId'],
      labels: List<String>.from(j['labels'] ?? []),
      priority: j['priority'] ?? 4,
      scheduled: DateTime.tryParse(j['scheduled'] ?? ''),
      recurrence: j['recurrence'] ?? '',
      recurrenceAnchor: DateTime.tryParse(j['recurrenceAnchor'] ?? ''),
      blockStart: DateTime.tryParse(j['blockStart'] ?? ''),
      fields: (j['fields'] as List? ?? [])
          .map((f) => TaskField.fromJson(Map<String, dynamic>.from(f)))
          .toList(),
      focusLogs: _readFocusLogs(j['focusLogs']),
      focusStartedAt: DateTime.tryParse(j['focusStartedAt'] ?? ''),
      focusMilliseconds: j['focusMilliseconds'] ?? 0,
      focusSessionId: j['focusSessionId'],
      attachments: (j['attachments'] as List? ?? [])
          .map((a) => Map<String, dynamic>.from(a))
          .toList(),
      comments: (j['comments'] as List? ?? [])
          .map((c) => Map<String, dynamic>.from(c))
          .toList(),
      reminder: DateTime.tryParse(j['reminder'] ?? ''),
      trashed: j['trashed'] ?? false,
      order: j['order'] ?? 0);
}

List<Map<String, dynamic>> _readFocusLogs(dynamic raw) {
  final logs =
      (raw as List? ?? []).map((v) => Map<String, dynamic>.from(v)).toList();
  final ids = <String>{};
  for (final log in logs) {
    if (log['id'] is! String ||
        !ids.add(log['id']) ||
        log['seconds'] is! int ||
        log['seconds'] < 0 ||
        log['seconds'] > 86400 ||
        log['endedAt'] is! String ||
        DateTime.tryParse(log['endedAt']) == null) {
      throw const FormatException('Invalid focus history.');
    }
  }
  return logs;
}

class TaskField {
  TaskField(this.name, this.type, this.value) {
    if (name.trim().isEmpty ||
        name.length > 40 ||
        !['Text', 'Number', 'Checkbox', 'Date'].contains(type)) {
      throw const FormatException('Choose a field name and supported type.');
    }
    if ((type == 'Text' &&
            (value is! String || (value as String).length > 500)) ||
        (type == 'Number' && (value is! num || !(value as num).isFinite)) ||
        (type == 'Checkbox' && value is! bool) ||
        (type == 'Date' &&
            (value is! String ||
                !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value as String) ||
                DateTime.tryParse(value as String) == null ||
                dayKey(DateTime.parse(value as String)) != value))) {
      throw const FormatException('Enter a valid value for this field type.');
    }
  }
  final String name, type;
  final Object value;
  String get display =>
      type == 'Checkbox' ? (value == true ? 'Yes' : 'No') : '$value';
  Map<String, dynamic> toJson() => {'name': name, 'type': type, 'value': value};
  factory TaskField.fromJson(Map<String, dynamic> json) =>
      TaskField(json['name'], json['type'], json['value']);
}

class GritEvent {
  GritEvent(this.id, this.title, this.type, this.date);
  final String id;
  String title, type;
  DateTime date;
  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'type': type, 'date': date.toIso8601String()};
  factory GritEvent.fromJson(Map<String, dynamic> j) =>
      GritEvent(j['id'], j['title'], j['type'], DateTime.parse(j['date']));
}

class PriorityEngine {
  const PriorityEngine(
      {this.importanceWeight = .6, this.urgencyWeight = .4, this.k = 48});
  final double importanceWeight, urgencyWeight, k;
  double urgency(Task t, DateTime now) => t.deadline == null
      ? .12
      : 1 / (1 + max(0, t.deadline!.difference(now).inMinutes / 60) / k);
  // Normalize importance so the specified weights actually control influence.
  double score(Task t, DateTime now, int remaining) =>
      t.importance / 5 * importanceWeight +
      urgency(t, now) * urgencyWeight +
      (remaining <= 60 && t.minutes <= remaining && t.minutes <= 25 ? 0.08 : 0);
  List<Task> rank(Iterable<Task> tasks, DateTime now, int capacity) {
    final list = tasks
        .where((t) =>
            !t.trashed &&
            !t.done(now) &&
            (t.overdue(now) ||
                t.snoozedUntil == null ||
                !t.snoozedUntil!.isAfter(now)))
        .toList();
    list.sort((a, b) {
      if (a.overdue(now) != b.overdue(now)) return a.overdue(now) ? -1 : 1;
      if ((a.pinnedDay == dayKey(now)) != (b.pinnedDay == dayKey(now))) {
        return a.pinnedDay == dayKey(now) ? -1 : 1;
      }
      if (a.order != b.order) return a.order.compareTo(b.order);
      final s = score(b, now, capacity).compareTo(score(a, now, capacity));
      return s != 0 ? s : a.id.compareTo(b.id);
    });
    return list;
  }

  List<Task> agenda(Iterable<Task> tasks, DateTime now, int capacity) {
    final result = <Task>[];
    var remaining = capacity;
    for (final t in rank(tasks, now, capacity)) {
      if (t.overdue(now) ||
          t.pinnedDay == dayKey(now) ||
          t.minutes <= remaining) {
        result.add(t);
        remaining -= t.minutes;
      }
    }
    return result;
  }

  String reason(Task t, DateTime now) => t.overdue(now)
      ? 'Deadline passed · needs your attention'
      : t.pinnedDay == dayKey(now)
          ? 'You chose this for today'
          : urgency(t, now) > .65
              ? 'Deadline approaching'
              : t.importance >= 4
                  ? 'High importance'
                  : t.minutes <= 25
                      ? 'A small step with real progress'
                      : 'Fits your available time';
}

int streak(Task task, DateTime now, {Set<String> freezes = const {}}) {
  var cursor = day(now);
  var count = 0;
  if (!task.history.contains(dayKey(cursor))) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  for (var i = 0; i < 3660; i++) {
    final key = dayKey(cursor);
    if (task.history.contains(key)) {
      count++;
    } else if (!freezes.contains(key)) {
      break;
    }
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return count;
}

int taskXp(Task t) => max(10, min(120, t.minutes ~/ 5 * 10));
