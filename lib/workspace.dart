import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'native_ui.dart';
import 'package:flutter/services.dart';
import 'design.dart';
import 'day_overview.dart';
import 'ios_surfaces.dart';
import 'schedule_drag.dart';
import 'timed_notice.dart';
import 'domain.dart';
import 'planning.dart';
import 'store.dart';
import 'recurrence.dart';
import 'platform_files.dart';
import 'calendar_export.dart';
import 'platform_bridge.dart';
import 'task_field_editor.dart';

Future<T?> ownedTextDialog<T>(BuildContext context,
    TextEditingController controller, WidgetBuilder builder) async {
  final route = DialogRoute<T>(context: context, builder: builder);
  final value = await Navigator.of(context, rootNavigator: true).push(route);
  // The popped future precedes the route's reverse animation.
  await route.completed;
  controller.dispose();
  return value;
}

class Workspace extends StatefulWidget {
  const Workspace({super.key, required this.store});
  final GritStore store;
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> with WidgetsBindingObserver {
  GritStore get s => widget.store;
  final scaffold = GlobalKey<ScaffoldState>();
  String view = 'Today', layout = 'List', sort = 'Manual', search = '';
  String? projectId, label, filterId;
  bool completed = false, selectMode = false;
  final selected = <String>{};
  final expandedTasks = <String>{};
  final completingTasks = <String>{};
  bool scheduleDragging = false;
  DateTime calendarDate = day(DateTime.now());
  DateTime lastToday = day(DateTime.now());
  bool get datedView => layout == 'Schedule' || layout == 'Calendar';
  String get selectedDayTitle {
    final today = day(DateTime.now());
    if (calendarDate == today) return 'Today';
    if (calendarDate == DateTime(today.year, today.month, today.day + 1)) {
      return 'Tomorrow';
    }
    if (calendarDate == DateTime(today.year, today.month, today.day - 1)) {
      return 'Yesterday';
    }
    return dateLabel(calendarDate);
  }

  void refreshDay() {
    final today = day(DateTime.now());
    if (calendarDate == lastToday) calendarDate = today;
    lastToday = today;
  }

  Timer? pulse;
  final notices = TimedNotice();
  final Set<String> notified = {};
  List<String> get views => [
        'Inbox',
        'Today',
        'Upcoming',
        'Filters & labels',
        'Completed',
        'Productivity',
        'Habits',
        'Events',
        'Activity',
        'Trash',
        'Settings'
      ];
  IconData viewIcon(String v) =>
      {
        'Inbox': Icons.inbox_outlined,
        'Today': Icons.today_outlined,
        'Upcoming': Icons.calendar_month_outlined,
        'Filters & labels': Icons.grid_view_rounded,
        'Completed': Icons.check_circle_outline,
        'Productivity': Icons.insights_outlined,
        'Habits': Icons.wb_sunny_outlined,
        'Events': Icons.flag_outlined,
        'Activity': Icons.history_rounded,
        'Trash': Icons.delete_outline,
        'Settings': Icons.tune_rounded
      }[v] ??
      Icons.tag;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (hasNativeBridge) {
      platformBridge.setMethodCallHandler((call) async {
        if (call.method == 'quickAdd' && mounted) {
          taskEditor(null, initialText: call.arguments as String?);
        }
        if (call.method == 'showToday' && mounted) navigate('Today');
      });
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final value =
              await platformBridge.invokeMethod<String>('takeQuickAdd');
          if (value != null && mounted) {
            taskEditor(null, initialText: value);
          }
        } on PlatformException catch (_) {
        } on MissingPluginException catch (_) {}
      });
    }
    pulse = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      unawaited(s.consumeWidgetCompletions());
      setState(refreshDay);
      for (final t in s.activeTasks.where((t) =>
          t.reminder != null &&
          !t.done(DateTime.now()) &&
          !t.reminder!.isAfter(DateTime.now()))) {
        final key = '${t.id}:${t.reminder}';
        if (notified.add(key)) {
          notices.show(context, 'Reminder · ${t.title}',
              duration: const Duration(seconds: 15),
              action: SnackBarAction(
                  label: 'Open', onPressed: () => taskDetail(t)));
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) setState(refreshDay);
      unawaited(s.consumeWidgetCompletions());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (hasNativeBridge) platformBridge.setMethodCallHandler(null);
    pulse?.cancel();
    notices.dispose();
    super.dispose();
  }

  void navigate(String target,
      {String? project, String? withLabel, String? withFilter}) {
    notices.dismiss();
    setState(() {
      view = target;
      calendarDate = day(DateTime.now());
      projectId = project;
      label = withLabel;
      filterId = withFilter;
      selected.clear();
      selectMode = false;
      search = '';
      layout = s.project(project)?.view ?? 'List';
    });
  }

  String get title => projectId != null
      ? s.project(projectId)?.name ?? 'Project'
      : label != null
          ? label!
          : filterId != null
              ? s.filters.where((f) => f.id == filterId).firstOrNull?.name ??
                  'Filter'
              : view == 'Today' && datedView
                  ? selectedDayTitle
                  : view;
  void toast(String text, {bool undo = false}) {
    final revision = s.undoRevision;
    notices.show(context, text,
        action: undo
            ? SnackBarAction(
                label: 'Undo',
                onPressed: () {
                  if (!s.undo(expectedRevision: revision)) {
                    // SnackBarAction hides its current bar after this callback.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        toast(
                            'A newer edit was made. Open the task to change it.');
                      }
                    });
                  }
                })
            : null);
  }

  List<Task> get visibleTasks {
    final now = DateTime.now();
    var list =
        (view == 'Trash' ? s.tasks.where((t) => t.trashed) : s.activeTasks)
            .where((t) => view == 'Completed'
                ? t.done(now)
                : view == 'Trash' ||
                    completed ||
                    (datedView && t.category == Category.habit) ||
                    !t.done(now))
            .toList();
    if (projectId != null) {
      list = list
          .where((t) => t.projectId == projectId && t.parentId == null)
          .toList();
    } else if (label != null) {
      list = list.where((t) => t.labels.contains(label)).toList();
    } else if (filterId != null) {
      final q =
          s.filters.where((f) => f.id == filterId).firstOrNull?.query ?? 'all';
      list = list
          .where((t) =>
              TaskQuery.matches(t, q, now, projectName: s.projectName(t)))
          .toList();
    } else if (view == 'Inbox') {
      list =
          list.where((t) => t.projectId == null && t.parentId == null).toList();
    } else if (datedView && (view == 'Today' || view == 'Upcoming')) {
      list = list.where((t) => t.parentId == null).toList();
    } else if (view == 'Today' && !datedView) {
      list = list
          .where((t) =>
              t.parentId == null &&
              ((t.scheduled != null && !day(t.scheduled!).isAfter(day(now))) ||
                  t.overdue(now) ||
                  t.pinnedDay == dayKey(now) ||
                  (t.category == Category.habit &&
                      (t.recurrence.isEmpty || t.recurrence == 'daily'))))
          .toList();
    } else if (view == 'Upcoming' && !datedView) {
      list = list
          .where((t) =>
              t.parentId == null &&
              t.scheduled != null &&
              !day(t.scheduled!).isBefore(day(now)))
          .toList();
    }
    if (search.isNotEmpty) {
      list = list
          .where((t) =>
              '${t.title} ${t.notes} ${s.projectName(t)} ${t.labels.join(' ')}'
                  .toLowerCase()
                  .contains(search.toLowerCase()))
          .toList();
    }
    list.sort((a, b) {
      if (sort == 'Priority') return a.priority.compareTo(b.priority);
      if (sort == 'Name') {
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      }
      if (sort == 'Date' || view == 'Upcoming') {
        return (a.scheduled ?? DateTime(2100))
            .compareTo(b.scheduled ?? DateTime(2100));
      }
      return a.order.compareTo(b.order);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
              openSearch,
          const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
              taskEditor(null),
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
              s.undo(),
          const SingleActivator(LogicalKeyboardKey.keyK, control: true):
              openSearch,
          const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
              taskEditor(null),
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
              s.undo()
        },
        child: Focus(
            autofocus: true,
            child: Scaffold(
                key: scaffold,
                drawer: wide
                    ? null
                    : Drawer(width: 290, child: SafeArea(child: sidebar())),
                floatingActionButton: wide
                    ? null
                    : FloatingActionButton(
                        tooltip: 'Add task',
                        onPressed: () => taskEditor(null),
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        child: const Icon(Icons.add_rounded, size: 28)),
                bottomNavigationBar: wide ? null : mobileNav(),
                body: SafeArea(
                    child: Row(children: [
                  if (wide) SizedBox(width: 248, child: sidebar()),
                  Expanded(
                      child: wide
                          ? Column(children: [
                              topbar(true),
                              if (s.error.isNotEmpty)
                                MaterialBanner(
                                    content: Text(s.error),
                                    actions: [
                                      TextButton(
                                          onPressed: () {
                                            s.error = '';
                                            s.save();
                                          },
                                          child: const Text('Dismiss'))
                                    ]),
                              Expanded(
                                  child: SingleChildScrollView(
                                      padding: const EdgeInsets.fromLTRB(
                                          46, 34, 46, 100),
                                      child: Align(
                                          alignment: Alignment.topCenter,
                                          child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                  maxWidth: 1160),
                                              child: body()))))
                            ])
                          : phoneScroll())
                ])))));
  }

  Widget sidebar() => Container(
      decoration: BoxDecoration(
          color: subtle(context),
          border: Border(right: BorderSide(color: hairline(context)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(23, 25, 20, 20),
            child: Row(children: [
              const GritMark(small: true),
              const Spacer(),
              IconButton(
                  tooltip: 'Notifications',
                  onPressed: reminders,
                  icon: Icon(Icons.notifications_none_rounded,
                      size: 20, color: secondary(context)))
            ])),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: InkWell(
                onTap: () => taskEditor(null),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(children: [
                      const Icon(Icons.add_circle_rounded,
                          color: accent, size: 22),
                      const SizedBox(width: 11),
                      const Expanded(
                          child: Text('Add task',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: accent,
                                  fontWeight: FontWeight.w600))),
                      keycap('⌘ N')
                    ])))),
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: navItem('Search', Icons.search_rounded,
                onTap: openSearch, trailing: keycap('⌘ K'))),
        Expanded(
            child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
              for (final v in views.take(4))
                navItem(v, viewIcon(v),
                    active: view == v &&
                        projectId == null &&
                        label == null &&
                        filterId == null,
                    count: countView(v),
                    onTap: () => navigate(v)),
              const SizedBox(height: 27),
              sidebarLabel('Favorites'),
              for (final p
                  in s.projects.where((p) => p.favorite && !p.archived))
                projectNav(p),
              for (final f in s.filters.where((f) => f.favorite))
                navItem(f.name, Icons.filter_alt_outlined,
                    active: filterId == f.id,
                    onTap: () => navigate('Filter', withFilter: f.id)),
              const SizedBox(height: 25),
              Row(children: [
                Expanded(child: sidebarLabel('My projects')),
                IconButton(
                    tooltip: 'Add project',
                    onPressed: () => projectEditor(),
                    icon: Icon(Icons.add, size: 17, color: secondary(context)))
              ]),
              for (final p in s.projectTree())
                DragTarget<Project>(
                    onWillAcceptWithDetails: (d) => d.data.id != p.id,
                    onAcceptWithDetails: (d) {
                      HapticFeedback.lightImpact();
                      s.reorderProject(d.data, p);
                    },
                    builder: (c, candidates, rejected) => Container(
                        color: candidates.isEmpty
                            ? null
                            : accent.withValues(alpha: .08),
                        child: LongPressDraggable<Project>(
                            onDragStarted: () =>
                                HapticFeedback.selectionClick(),
                            onDragCompleted: () => HapticFeedback.lightImpact(),
                            data: p,
                            feedback: Material(
                                child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(p.name))),
                            child: Padding(
                                padding: EdgeInsets.only(
                                    left: s.projectDepth(p) * 12.0),
                                child: projectNav(p))))),
              navItem('Browse templates', Icons.dashboard_customize_outlined,
                  onTap: templates),
              const SizedBox(height: 22),
              sidebarLabel('Your space'),
              for (final v in [
                'Productivity',
                'Habits',
                'Events',
                'Activity',
                'Completed'
              ])
                navItem(v, viewIcon(v),
                    active: view == v, onTap: () => navigate(v))
            ])),
        Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              if (s.gamification)
                Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                        color: surface(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: hairline(context))),
                    child: Row(children: [
                      Icon(Icons.spa_outlined, color: sage, size: 21),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            const Text('A little, every day.',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600)),
                            Text(
                                '${s.completedOn(DateTime.now())} of ${s.dailyGoal} daily tasks',
                                style: TextStyle(
                                    color: secondary(context), fontSize: 10))
                          ])),
                      SizedBox(
                          width: 25,
                          height: 25,
                          child: CircularProgressIndicator(
                              value: min(1,
                                  s.completedOn(DateTime.now()) / s.dailyGoal),
                              strokeWidth: 3,
                              color: sage,
                              backgroundColor: hairline(context)))
                    ])),
              const SizedBox(height: 15),
              InkWell(
                  onTap: () => navigate('Settings'),
                  child: Row(children: [
                    avatar(),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(s.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13))),
                    Icon(Icons.settings_outlined,
                        color: secondary(context), size: 18)
                  ]))
            ]))
      ]));
  Widget sidebarLabel(String text) => Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: secondary(context))));
  Widget keycap(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
          border: Border.all(color: hairline(context)),
          borderRadius: BorderRadius.circular(4)),
      child:
          Text(text, style: TextStyle(color: secondary(context), fontSize: 9)));
  Widget avatar() => CircleAvatar(
      radius: 15,
      backgroundColor: const Color(0xFFEADDD1),
      child: Text(s.name.isEmpty ? 'G' : s.name[0].toUpperCase(),
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF92715B))));
  int? countView(String v) {
    final open = s.activeTasks
        .where((t) => !t.done(DateTime.now()) && t.parentId == null);
    if (v == 'Inbox') return open.where((t) => t.projectId == null).length;
    if (v == 'Today') {
      return open
          .where((t) =>
              t.scheduled != null &&
              !day(t.scheduled!).isAfter(day(DateTime.now())))
          .length;
    }
    return null;
  }

  Widget navItem(String text, IconData icon,
          {bool active = false,
          int? count,
          VoidCallback? onTap,
          Widget? trailing,
          Color? color}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Material(
              color:
                  active ? accent.withValues(alpha: .10) : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () {
                    onTap?.call();
                    if (scaffold.currentState?.isDrawerOpen ?? false) {
                      Navigator.pop(context);
                    }
                  },
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(children: [
                        Icon(icon,
                            size: 19,
                            color: color ??
                                (active ? accent : secondary(context))),
                        const SizedBox(width: 11),
                        Expanded(
                            child: Text(text,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: active
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: active ? accent : null))),
                        if (count != null && count > 0)
                          Text('$count',
                              style: TextStyle(
                                  color: active ? accent : secondary(context),
                                  fontSize: 11)),
                        if (trailing != null) trailing
                      ])))));
  Widget projectNav(Project p) => navItem(p.name, Icons.tag,
      trailing: projectProgress(p),
      color: Color(p.color),
      active: projectId == p.id,
      count: s.activeTasks
          .where((t) =>
              t.projectId == p.id &&
              t.parentId == null &&
              !t.done(DateTime.now()))
          .length,
      onTap: () => navigate('Project', project: p.id));
  Widget projectProgress(Project p) {
    final tasks = s.activeTasks
        .where((t) => t.projectId == p.id && t.parentId == null)
        .toList();
    final completed = tasks.where((t) => t.done(DateTime.now())).length;
    return Padding(
        padding: const EdgeInsets.only(left: 10),
        child: Tooltip(
            message: '$completed of ${tasks.length} tasks complete',
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    value: tasks.isEmpty ? 0 : completed / tasks.length,
                    strokeWidth: 2.5,
                    color: Color(p.color),
                    backgroundColor: hairline(context)))));
  }

  Widget topbar(bool wide) => Container(
      height: 62,
      padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 14),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: hairline(context)))),
      child: Row(children: [
        if (!wide)
          IconButton(
              tooltip: 'Open navigation',
              onPressed: () => scaffold.currentState?.openDrawer(),
              icon: const Icon(Icons.menu_rounded, size: 22)),
        if (wide) ...[
          Icon(projectId == null ? Icons.person_outline : Icons.tag,
              size: 16, color: secondary(context)),
          const SizedBox(width: 8),
          Text(s.previewMode ? 'Sample workspace' : 'My workspace',
              style: TextStyle(color: secondary(context), fontSize: 12)),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('/', style: TextStyle(color: secondary(context))))
        ],
        Expanded(
            child: Text(wide ? title : 'grit',
                style: TextStyle(
                    fontSize: wide ? 12 : 23,
                    fontWeight: wide ? FontWeight.w500 : FontWeight.w800,
                    letterSpacing: wide ? 0 : -1))),
        if (wide && s.gamification)
          Row(children: [
            Icon(Icons.check_circle_outline, size: 16, color: sage),
            const SizedBox(width: 7),
            Text('${s.completedOn(DateTime.now())}/${s.dailyGoal}',
                style: TextStyle(color: secondary(context), fontSize: 11)),
            const SizedBox(width: 19)
          ]),
        IconButton(
            tooltip: 'Search tasks',
            onPressed: openSearch,
            icon: Icon(Icons.search_rounded,
                size: 20, color: secondary(context))),
        IconButton(
            tooltip: 'Settings',
            onPressed: () => navigate('Settings'),
            icon:
                Icon(Icons.tune_rounded, size: 19, color: secondary(context))),
        if (wide) ...[const SizedBox(width: 10), avatar()]
      ]));
  Widget mobileNav() {
    final index = ['Today', 'Upcoming', 'Inbox'].indexOf(view);
    // UIKit tab labels keep their standard size; content retains Dynamic Type.
    return MediaQuery.withNoTextScaling(
        child: CupertinoTabBar(
            currentIndex: index < 0 ? 3 : index,
            activeColor: accent,
            inactiveColor: secondary(context),
            backgroundColor: surface(context).withValues(alpha: .96),
            onTap: (i) {
              HapticFeedback.selectionClick();
              if (i == 3) {
                scaffold.currentState?.openDrawer();
              } else {
                navigate(['Today', 'Upcoming', 'Inbox'][i]);
              }
            },
            items: const [
          BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.sun_max),
              activeIcon: Icon(CupertinoIcons.sun_max_fill),
              label: 'Today'),
          BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.calendar), label: 'Upcoming'),
          BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.tray),
              activeIcon: Icon(CupertinoIcons.tray_fill),
              label: 'Inbox'),
          BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.square_grid_2x2), label: 'Browse')
        ]));
  }

  Widget phoneScroll() => CustomScrollView(
          key: ValueKey('phone-$title'),
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            CupertinoSliverNavigationBar(
                largeTitle: Text(title),
                automaticBackgroundVisibility: false,
                backgroundColor: canvas(context).withValues(alpha: .95),
                border: null,
                leading: IconButton(
                    tooltip: 'Open navigation',
                    onPressed: () => scaffold.currentState?.openDrawer(),
                    icon:
                        const Icon(CupertinoIcons.line_horizontal_3, size: 23)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      tooltip: 'Search tasks',
                      onPressed: openSearch,
                      icon: const Icon(CupertinoIcons.search, size: 22)),
                  IconButton(
                      tooltip: 'Settings',
                      onPressed: () => navigate('Settings'),
                      icon: const Icon(CupertinoIcons.slider_horizontal_3,
                          size: 22))
                ])),
            CupertinoSliverRefreshControl(
                refreshIndicatorExtent: 60,
                builder: (c, mode, pulled, trigger, extent) => GritRefreshGlyph(
                    progress: pulled / trigger,
                    refreshing: mode == RefreshIndicatorMode.refresh,
                    complete: mode == RefreshIndicatorMode.done),
                onRefresh: () async {
                  HapticFeedback.selectionClick();
                  await s.recordSync?.cycle();
                  if (mounted) {
                    setState(() {});
                    toast(s.recordSync == null
                        ? 'Your local tasks are up to date.'
                        : s.error.isEmpty
                            ? 'Tasks refreshed.'
                            : 'Saved locally. Cloud is not connected.');
                  }
                }),
            if (s.error.isNotEmpty)
              SliverToBoxAdapter(
                  child: MaterialBanner(content: Text(s.error), actions: [
                TextButton(
                    onPressed: () {
                      s.error = '';
                      s.save();
                    },
                    child: const Text('Dismiss'))
              ])),
            SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                sliver: SliverToBoxAdapter(child: body()))
          ]);

  Widget body() {
    if (view == 'Filters & labels') return filtersPage();
    if (view == 'Productivity') return productivity();
    if (view == 'Habits') return habitsPage();
    if (view == 'Events') return eventsPage();
    if (view == 'Activity') return activityPage();
    if (view == 'Settings') return settingsPage();
    return tasksPage();
  }

  Widget pageHeader(String heading, String subtitle, {Widget? action}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  if (!compactPlatform(context))
                    Text(heading,
                        style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 8),
                  Text(subtitle,
                      style: TextStyle(color: secondary(context), fontSize: 13))
                ])),
            if (action != null) action
          ]));
  Widget tasksPage() {
    final scoped = visibleTasks;
    final now = datedView ? calendarDate : DateTime.now();
    final list = layout == 'Schedule'
        ? planningDayTasks(scoped, calendarDate,
            now: DateTime.now(),
            carryOver: view == 'Today' && projectId == null,
            includeUndated: view != 'Today' || projectId != null,
            includeCompleted: completed)
        : scoped;
    final summaryList = layout == 'Calendar'
        ? planningDayTasks(scoped, calendarDate,
            now: DateTime.now(), includeCompleted: completed)
        : list;
    final hasSidebar = MediaQuery.sizeOf(context).width >= 1320 &&
        view == 'Today' &&
        !datedView;
    final main =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      pageHeader(
          title,
          view == 'Today'
              ? '${weekdayName(now.weekday)}, ${monthName(now.month)} ${now.day}'
              : projectId != null
                  ? (s.project(projectId)?.description ?? '').isEmpty
                      ? 'A space for the things you’re working towards.'
                      : s.project(projectId)?.description ?? ''
                  : view == 'Upcoming'
                      ? 'A little perspective on the days ahead.'
                      : view == 'Inbox'
                          ? 'Catch a thought. Make a plan later.'
                          : view == 'Completed'
                              ? 'A record of the things you made happen.'
                              : view == 'Trash'
                                  ? 'Deleted tasks stay here until you restore them.'
                                  : 'Your tasks, with a little more clarity.',
          action: GritMenuButton<String>(
              tooltip: 'View options',
              icon: Icon(Icons.more_horiz, color: secondary(context)),
              onSelected: (v) {
                if (v == 'project') projectEditor(s.project(projectId));
                if (v == 'import') bulkImport();
                if (v == 'select') setState(() => selectMode = !selectMode);
                if (v == 'completed') setState(() => completed = !completed);
              },
              itemBuilder: (c) => [
                    if (projectId != null)
                      const PopupMenuItem(
                          value: 'project', child: Text('Edit project')),
                    const PopupMenuItem(
                        value: 'select', child: Text('Select multiple tasks')),
                    PopupMenuItem(
                        value: 'completed',
                        child: Text(
                            completed ? 'Hide completed' : 'Show completed')),
                    const PopupMenuItem(
                        value: 'import', child: Text('Paste a task list'))
                  ])),
      if (view == 'Today' &&
          search.isEmpty &&
          !selectMode &&
          summaryList.isNotEmpty)
        DayOverview(
          remaining: summaryList.where((t) => !t.done(now)).length,
          completed: s.completedOn(now),
          minutes: summaryList
              .where((t) => !t.done(now))
              .fold<int>(0, (n, t) => n + t.minutes),
          onFocus: summaryList.where((t) => !t.done(now)).isEmpty
              ? null
              : () => focus(summaryList.firstWhere((t) => !t.done(now))),
          onPlan: () => setState(() => layout = 'Schedule'),
        ),
      if (projectId != null) projectSummary(),
      if (view == 'Today' && s.gamification && !datedView) dailyNote(),
      const SizedBox(height: 4),
      Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 12,
          spacing: 16,
          children: [
            projectViewControl(),
            GritMenuButton<String>(
                tooltip: 'Sort tasks',
                onSelected: (v) => setState(() => sort = v),
                itemBuilder: (c) => ['Manual', 'Priority', 'Date', 'Name']
                    .map((v) => PopupMenuItem(value: v, child: Text(v)))
                    .toList(),
                child: Padding(
                    padding: const EdgeInsets.all(9),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.swap_vert,
                          size: 16, color: secondary(context)),
                      const SizedBox(width: 5),
                      Flexible(
                          child: Text('Sort: $sort',
                              style: TextStyle(
                                  color: secondary(context), fontSize: 11))),
                      const SizedBox(width: 5),
                      Icon(Icons.expand_more,
                          size: 14, color: secondary(context))
                    ])))
          ]),
      const SizedBox(height: 23),
      if (selectMode) bulkToolbar(),
      if (layout == 'Board' || layout == 'Calendar')
        Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
                layout == 'Board'
                    ? 'Long-press to move a task between columns. Drop onto Calendar to switch views.'
                    : 'Drag tasks onto dates to schedule them. Drop onto Board to switch views.',
                style: TextStyle(fontSize: 12, color: secondary(context)))),
      if (layout == 'Schedule')
        scheduleView(list)
      else if (layout == 'Calendar')
        calendarView(list)
      else if (layout == 'Board')
        boardView(list)
      else if (view == 'Upcoming')
        upcomingDays(list)
      else
        taskGroups(list),
      if (view != 'Completed' && view != 'Trash') addRow(),
      if (view == 'Today' && search.isEmpty && layout == 'List')
        projectOverview(),
      if (list.isNotEmpty && view == 'Today')
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.spa_outlined, size: 15, color: sage),
              const SizedBox(width: 8),
              Flexible(
                  child: Text('One thing at a time is a perfectly good plan.',
                      style:
                          TextStyle(color: secondary(context), fontSize: 11)))
            ]))
    ]);
    return hasSidebar
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: main),
            const SizedBox(width: 48),
            SizedBox(width: 248, child: daySidebar())
          ])
        : main;
  }

  void selectProjectLayout(String item, {Task? carried}) {
    HapticFeedback.selectionClick();
    setState(() {
      layout = item;
      if (carried?.scheduled != null) calendarDate = day(carried!.scheduled!);
    });
    final p = s.project(projectId);
    if (p != null) {
      p.view = item;
      s.save();
    }
  }

  Widget projectViewControl() {
    const views = ['List', 'Board', 'Calendar', 'Schedule'];
    if (compactPlatform(context) &&
        MediaQuery.textScalerOf(context).scale(13) > 20) {
      return SizedBox(
          width: MediaQuery.sizeOf(context).width - 40,
          child: GritChoiceField<String>(
              initialValue: layout,
              decoration: const InputDecoration(labelText: 'View'),
              items: views
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) {
                if (v != null) selectProjectLayout(v);
              }));
    }
    Widget label(String item) => DragTarget<Task>(
        key: ValueKey('project-view-$item'),
        onWillAcceptWithDetails: (_) => layout != item,
        onAcceptWithDetails: (details) =>
            selectProjectLayout(item, carried: details.data),
        builder: (c, candidates, rejected) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            decoration: BoxDecoration(
                color:
                    candidates.isEmpty ? null : accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(9)),
            child: Text(item,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        layout == item ? FontWeight.w600 : FontWeight.w400,
                    color: layout == item
                        ? Theme.of(context).colorScheme.onSurface
                        : secondary(context)))));
    if (compactPlatform(context)) {
      return CupertinoSlidingSegmentedControl<String>(
          groupValue: layout,
          backgroundColor: subtle(context),
          thumbColor: surface(context),
          onValueChanged: (v) {
            if (v != null) selectProjectLayout(v);
          },
          children: {for (final item in views) item: label(item)});
    }
    return Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
            color: subtle(context), borderRadius: BorderRadius.circular(12)),
        child: Wrap(children: [
          for (final item in views)
            InkWell(onTap: () => selectProjectLayout(item), child: label(item))
        ]));
  }

  Widget projectSummary() {
    final p = s.project(projectId)!;
    final tasks = s.activeTasks
        .where((t) => t.projectId == p.id && t.parentId == null)
        .toList();
    final done = tasks.where((t) => t.done(DateTime.now())).length;
    final color = Color(p.color);
    return Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: DetailGroup(
            child: Row(children: [
          SizedBox(
              width: 46,
              height: 46,
              child: Semantics(
                  label: '$done of ${tasks.length} tasks complete',
                  child: CircularProgressIndicator(
                      value: tasks.isEmpty ? 0 : done / tasks.length,
                      strokeWidth: 4,
                      color: color,
                      backgroundColor: color.withValues(alpha: .14)))),
          const SizedBox(width: 18),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('${tasks.length - done} tasks to go',
                    style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.5)),
                const SizedBox(height: 4),
                Text(
                    '$done completed · ${tasks.where((t) => !t.done(DateTime.now())).fold<int>(0, (n, t) => n + t.minutes)} min estimated',
                    style: TextStyle(fontSize: 13, color: secondary(context))),
              ])),
        ])));
  }

  Widget projectOverview() {
    final projects = s.projects.where((p) => !p.archived).take(4).toList();
    if (projects.isEmpty) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.only(top: 30),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
                child: Text('Your spaces',
                    style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.5))),
            IconButton(
                tooltip: 'Create project',
                onPressed: () => projectEditor(),
                icon: const Icon(Icons.add_rounded))
          ]),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            final wideText = MediaQuery.textScalerOf(context).scale(16) > 24;
            final width = wideText
                ? constraints.maxWidth
                : (constraints.maxWidth - 12) / 2;
            return Wrap(spacing: 12, runSpacing: 12, children: [
              for (final p in projects)
                SizedBox(
                    width: width,
                    child: ProjectProgressCard(
                        name: p.name,
                        color: Color(p.color),
                        done: s.activeTasks
                            .where((t) =>
                                t.projectId == p.id && t.done(DateTime.now()))
                            .length,
                        total: s.activeTasks
                            .where((t) => t.projectId == p.id)
                            .length,
                        onTap: () => navigate('Project', project: p.id)))
            ]);
          }),
        ]));
  }

  Widget dailyNote() {
    final done = s.completedOn(DateTime.now());
    return Container(
        margin: const EdgeInsets.only(bottom: 25),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        decoration: BoxDecoration(
            color: subtle(context), borderRadius: BorderRadius.circular(13)),
        child: Row(children: [
          Container(
              width: 35,
              height: 35,
              decoration: BoxDecoration(
                  color: sage.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(11)),
              child:
                  const Icon(Icons.wb_sunny_outlined, size: 20, color: sage)),
          const SizedBox(width: 13),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                    done >= s.dailyGoal
                        ? 'Look at you. Daily goal reached.'
                        : 'A fresh page, ${s.name}.',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 3),
                Text(
                    '$done of ${s.dailyGoal} tasks complete. Every little step counts.',
                    style: TextStyle(color: secondary(context), fontSize: 11))
              ])),
          const SizedBox(width: 12),
          SizedBox(
              width: 34,
              height: 34,
              child: Stack(alignment: Alignment.center, children: [
                CircularProgressIndicator(
                    value: min(1, done / s.dailyGoal),
                    strokeWidth: 3,
                    color: sage,
                    backgroundColor: sage.withValues(alpha: .13)),
                Text('$done',
                    style: const TextStyle(
                        fontSize: 11, color: sage, fontWeight: FontWeight.w600))
              ]))
        ]));
  }

  Widget daySidebar() {
    final now = DateTime.now();
    final agenda = s.engine.agenda(
        s.activeTasks.where((t) => t.parentId == null),
        now,
        s.remainingCapacity);
    return Column(children: [
      const SizedBox(height: 8),
      SoftCard(
          color: subtle(context),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.calendar_today_outlined,
                  size: 14, color: secondary(context)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('${monthName(now.month)} ${now.year}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600))),
              Icon(Icons.expand_more, size: 15, color: secondary(context))
            ]),
            const SizedBox(height: 23),
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(7, (i) {
                  final d =
                      day(now).subtract(Duration(days: now.weekday - 1 - i));
                  final active = dayKey(d) == dayKey(now);
                  return InkWell(
                      onTap: () {
                        navigate('Upcoming');
                        setState(() {
                          calendarDate = d;
                          layout = 'Calendar';
                        });
                      },
                      child: Column(children: [
                        Text(weekdayName(i + 1).substring(0, 1),
                            style: TextStyle(
                                color: secondary(context), fontSize: 10)),
                        const SizedBox(height: 10),
                        Container(
                            width: 25,
                            height: 31,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: active ? accent : Colors.transparent,
                                borderRadius: BorderRadius.circular(8)),
                            child: Text('${d.day}',
                                style: TextStyle(
                                    color: active ? Colors.white : null,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)))
                      ]));
                }))
          ])),
      const SizedBox(height: 22),
      SoftCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.filter_center_focus, size: 16, color: violet),
          const SizedBox(width: 8),
          const Expanded(
              child: Text('A little room to focus',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)))
        ]),
        const SizedBox(height: 8),
        Text('Your next best step, picked around your time and priorities.',
            style: TextStyle(fontSize: 11, color: secondary(context))),
        const SizedBox(height: 20),
        if (agenda.isNotEmpty) ...[
          Text(agenda.first.title,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14, height: 1.5)),
          const SizedBox(height: 8),
          Pill('${agenda.first.minutes} min',
              icon: Icons.schedule, color: violet),
          const SizedBox(height: 19),
          SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      side: BorderSide(color: hairline(context)),
                      padding: const EdgeInsets.all(15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  onPressed: () => focus(agenda.first),
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: const Text('Start a focus session',
                      style: TextStyle(fontSize: 11))))
        ] else
          const Text('You have room to breathe.',
              style: TextStyle(fontSize: 13)),
        const SizedBox(height: 12),
        Text('${s.remainingCapacity} minutes left in your daily plan',
            style: TextStyle(color: secondary(context), fontSize: 10))
      ])),
      const SizedBox(height: 30),
      const QuietIllustration(size: 125),
      const SizedBox(height: 15),
      const Text('Good things take a little time.',
          style: TextStyle(fontSize: 11, color: sage)),
      const SizedBox(height: 25),
      TextButton.icon(
          onPressed: () => navigate('Productivity'),
          icon: const Icon(Icons.insights_outlined, size: 15),
          label:
              const Text('See your progress', style: TextStyle(fontSize: 11)))
    ]);
  }

  Widget groupHeader(String text, int count,
          {Color? color, VoidCallback? action}) =>
      Padding(
          padding: const EdgeInsets.only(top: 9, bottom: 6),
          child: Row(children: [
            Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: color))),
            Text('$count',
                style: TextStyle(fontSize: 11, color: secondary(context))),
            if (projectId != null &&
                (s.project(projectId)?.sections.contains(text) ?? false))
              IconButton(
                  tooltip: 'Edit section',
                  onPressed: () => sectionEditor(text),
                  icon: Icon(Icons.more_horiz,
                      size: 16, color: secondary(context))),
            if (action != null)
              IconButton(
                  tooltip: text == 'Labels'
                      ? 'Manage labels'
                      : 'Add task to section',
                  onPressed: action,
                  icon: Icon(Icons.add, size: 16, color: secondary(context)))
          ]));
  Widget upcomingDays(List<Task> list) {
    final dates = {
      for (var i = 0; i < 14; i++) day(DateTime.now()).add(Duration(days: i)),
      ...list.map((t) => day(t.scheduled!))
    }.toList()
      ..sort();
    return Column(children: [
      for (final date in dates)
        DragTarget<Task>(
            onWillAcceptWithDetails: (d) => !d.data.trashed,
            onAcceptWithDetails: (d) {
              final old = d.data.scheduled;
              s.schedule(
                  d.data,
                  DateTime(date.year, date.month, date.day, old?.hour ?? 0,
                      old?.minute ?? 0));
              toast('Moved to ${dateLabel(date)}', undo: true);
            },
            builder: (c, candidates, rejected) => Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                    color: candidates.isEmpty
                        ? null
                        : accent.withValues(alpha: .06),
                    border: Border(bottom: BorderSide(color: hairline(c)))),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      groupHeader(
                          '${weekdayName(date.weekday)} · ${dateLabel(date)}',
                          list
                              .where(
                                  (t) => dayKey(t.scheduled!) == dayKey(date))
                              .length,
                          action: () => taskEditor(null, date: date)),
                      for (final t in list
                          .where((t) => dayKey(t.scheduled!) == dayKey(date)))
                        taskRow(t),
                      if (!list
                          .any((t) => dayKey(t.scheduled!) == dayKey(date)))
                        Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text('Drop a task here or add one',
                                style: TextStyle(
                                    fontSize: 11, color: secondary(c))))
                    ])))
    ]);
  }

  Widget taskGroups(List<Task> list) {
    if (list.isEmpty) {
      if (search.isNotEmpty) {
        return emptyState('No matching tasks.',
            'Try a different word, or clear your search to see this view again.',
            actionLabel: 'Clear search',
            onAction: () => setState(() => search = ''),
            icon: Icons.search_rounded);
      }
      if (view == 'Completed') {
        return emptyState('Small steps add up.',
            'Tasks you complete will appear here. Your next step is waiting in Today.',
            actionLabel: 'Go to Today',
            onAction: () => navigate('Today'),
            icon: Icons.check_circle_outline);
      }
      if (view == 'Trash') {
        return emptyState('Nothing in the bin.',
            'Deleted tasks stay here so you can bring them back when you need them.',
            icon: Icons.restore_rounded);
      }
      if (projectId != null) {
        return emptyState('Give this project a first step.',
            'Start with one manageable task. You can organize it into sections as your plan grows.',
            actionLabel: 'Add first task',
            onAction: () => taskEditor(null),
            icon: Icons.layers_outlined);
      }
      if (view == 'Filter' || view == 'Label') {
        return emptyState('All clear here.',
            'Tasks that match this view will appear here. Your other tasks are still in their projects.',
            actionLabel: 'Go to Today',
            onAction: () => navigate('Today'),
            icon: Icons.filter_alt_outlined);
      }
      return emptyState(
          view == 'Today'
              ? 'A little breathing room.'
              : 'A home for your next idea.',
          view == 'Today'
              ? 'Your day has space. Add one thing that matters, or enjoy the pause.'
              : 'Capture a thought now. Choose a project or a date when you’re ready.',
          actionLabel: view == 'Today' ? 'Plan a task' : 'Capture a task',
          onAction: () => taskEditor(null),
          icon:
              view == 'Today' ? Icons.wb_sunny_outlined : Icons.inbox_outlined);
    }
    final groups = <String, List<Task>>{};
    for (final t in list) {
      String key = '';
      if (view == 'Today') {
        key = t.scheduled != null &&
                    day(t.scheduled!).isBefore(day(DateTime.now())) ||
                t.overdue(DateTime.now())
            ? 'Overdue'
            : 'Today';
      } else if (view == 'Upcoming') {
        key =
            '${weekdayName(t.scheduled!.weekday)} · ${dateLabel(t.scheduled!)}';
      } else if (projectId != null) {
        key = t.section.isEmpty ? 'Unsectioned' : t.section;
      } else {
        key = view == 'Completed'
            ? 'Completed tasks'
            : view == 'Trash'
                ? 'Recently deleted'
                : 'Tasks';
      }
      groups.putIfAbsent(key, () => []).add(t);
    }
    final project = s.project(projectId);
    if (project != null) {
      for (final section in project.sections) {
        groups.putIfAbsent(section, () => []);
      }
    }
    final keys = project == null
        ? groups.keys.toList()
        : [
            ...project.sections,
            ...groups.keys.where((k) => !project.sections.contains(k))
          ];
    if (view == 'Today') {
      keys.sort((a, b) => a == 'Overdue'
          ? -1
          : b == 'Overdue'
              ? 1
              : 0);
    }
    return Column(children: [
      for (final key in keys) ...[
        groupHeader(key, groups[key]!.length,
            color: key == 'Overdue' ? accent : null,
            action: projectId != null
                ? () =>
                    taskEditor(null, section: key == 'Unsectioned' ? '' : key)
                : null),
        ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: groups[key]!.length,
            onReorderStart: (_) => HapticFeedback.selectionClick(),
            proxyDecorator: (child, index, animation) =>
                SpringLift(child: child),
            onReorder: (oldIndex, newIndex) {
              HapticFeedback.lightImpact();
              if (newIndex > oldIndex) newIndex--;
              final ordered = groups[key]!;
              s.checkpoint();
              final task = ordered.removeAt(oldIndex);
              ordered.insert(newIndex, task);
              for (var i = 0; i < ordered.length; i++) {
                ordered[i].order = i;
              }
              s.save();
            },
            itemBuilder: (c, i) =>
                Row(key: ValueKey(groups[key]![i].id), children: [
                  Expanded(child: taskRow(groups[key]![i])),
                  if (selectMode)
                    ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Tooltip(
                                message: 'Drag to reorder',
                                child: Icon(CupertinoIcons.line_horizontal_3,
                                    size: 20))))
                ])),
        const SizedBox(height: 22)
      ],
      if (projectId != null)
        TextButton.icon(
            onPressed: addSection,
            icon: const Icon(Icons.add, size: 17),
            label: const Text('Add section'))
    ]);
  }

  Widget taskRow(Task t, {bool nested = false, bool card = false}) {
    final children = s.activeTasks.where((x) => x.parentId == t.id).toList();
    return TaskCompletionMotion(
        key: ValueKey('completion-${t.id}'),
        completing: completingTasks.contains(t.id),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              swipeTaskRow(t, nested: nested, card: card),
              if (children.isNotEmpty && !card) ...[
                TextButton.icon(
                    onPressed: () => setState(() => expandedTasks.contains(t.id)
                        ? expandedTasks.remove(t.id)
                        : expandedTasks.add(t.id)),
                    icon: Icon(
                        expandedTasks.contains(t.id)
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 16),
                    label: Text(
                        '${expandedTasks.contains(t.id) ? 'Hide' : 'Show'} ${children.length} subtasks',
                        style: const TextStyle(fontSize: 11))),
                if (expandedTasks.contains(t.id))
                  Padding(
                      padding: const EdgeInsets.only(left: 18),
                      child: Column(children: [
                        for (final child in children)
                          taskRow(child, nested: true)
                      ]))
              ]
            ]));
  }

  Widget swipeTaskRow(Task t, {bool nested = false, bool card = false}) {
    final content = _taskRow(t, nested: nested, card: card);
    if (card || selectMode || t.trashed) return content;
    return SwipeTaskActions(
        key: ValueKey('swipe-${t.id}'),
        child: content,
        complete: () => completeTask(t),
        schedule: () => scheduleActions(t),
        delete: () {
          HapticFeedback.mediumImpact();
          s.deleteTask(t);
          toast('Moved to Trash', undo: true);
        });
  }

  Future<void> scheduleActions(Task task) async {
    final choice = await gritActions(context, 'Schedule task', {
      'today': 'Today',
      'tomorrow': 'Tomorrow',
      'date': 'Choose date and time',
      'none': 'Remove date'
    });
    if (!mounted || choice == null) return;
    if (choice == 'date') {
      final date =
          await pickGritDate(context, task.scheduled ?? DateTime.now());
      if (date != null) s.schedule(task, date);
    } else {
      s.schedule(
          task,
          choice == 'none'
              ? null
              : day(DateTime.now())
                  .add(Duration(days: choice == 'tomorrow' ? 1 : 0)));
    }
    HapticFeedback.selectionClick();
  }

  Future<void> taskQuickActions(Task task) async {
    final choice = await gritActions(context, task.title, {
      'edit': 'Edit task',
      'schedule': 'Schedule',
      'focus': 'Start focus session',
      'move': 'Move to project',
      'duplicate': 'Duplicate',
      'select': 'Select tasks',
      'trash': 'Move to Trash'
    }, destructive: {
      'trash'
    });
    if (!mounted || choice == null) return;
    if (choice == 'schedule') {
      scheduleActions(task);
    } else if (choice == 'select') {
      setState(() {
        selectMode = true;
        selected.add(task.id);
      });
    } else {
      taskAction(task, choice);
    }
  }

  Widget _taskRow(Task t, {bool nested = false, bool card = false}) {
    final now = datedView ? calendarDate : DateTime.now();
    final done = t.done(now);
    final subs = s.activeTasks.where((x) => x.parentId == t.id).toList();
    final color = priorityColor(t.priority);
    final p = s.project(t.projectId);
    return Container(
        decoration: BoxDecoration(
            color: Color.alphaBlend(
                categoryAccent(t).withValues(alpha: .025), surface(context)),
            borderRadius: BorderRadius.circular(card ? 20 : 16),
            border: Border.all(
                color: Color.alphaBlend(
                    categoryAccent(t).withValues(alpha: .18),
                    hairline(context)))),
        margin: const EdgeInsets.only(bottom: 8),
        child: Material(
            color: Colors.transparent,
            child: InkWell(
                onTap: () => selectMode
                    ? setState(() => selected.contains(t.id)
                        ? selected.remove(t.id)
                        : selected.add(t.id))
                    : taskDetail(t),
                onLongPress: card ? null : () => taskQuickActions(t),
                child: Padding(
                    padding: EdgeInsets.fromLTRB(
                        nested
                            ? 20
                            : card
                                ? 8
                                : 8,
                        s.taskPadding,
                        8,
                        s.taskPadding - 1),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                              width: 44,
                              height: 44,
                              child: selectMode
                                  ? Checkbox(
                                      value: selected.contains(t.id),
                                      onChanged: (v) => setState(() => v == true
                                          ? selected.add(t.id)
                                          : selected.remove(t.id)))
                                  : IconButton(
                                      padding: EdgeInsets.zero,
                                      tooltip: done
                                          ? 'Reopen ${t.title}'
                                          : 'Complete ${t.title}',
                                      onPressed: () => completeTask(t),
                                      icon: SpringCheck(
                                          checked: done ||
                                              completingTasks.contains(t.id),
                                          color: done ? sage : color))),
                          const SizedBox(width: 5),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(t.title,
                                    style: TextStyle(
                                        fontSize:
                                            compactPlatform(context) ? 17 : 14,
                                        fontWeight: FontWeight.w500,
                                        decoration: done
                                            ? TextDecoration.lineThrough
                                            : null,
                                        color: done ? secondary(context) : null,
                                        height: 1.5)),
                                if (t.notes.isNotEmpty &&
                                    !nested &&
                                    s.density != 'Compact') ...[
                                  const SizedBox(height: 4),
                                  Text(t.notes,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: secondary(context),
                                          fontSize: 11))
                                ],
                                const SizedBox(height: 7),
                                Wrap(
                                    spacing: 10,
                                    runSpacing: 5,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      if (card)
                                        meta('${t.minutes} min',
                                            Icons.schedule_outlined,
                                            color: sage),
                                      if (card)
                                        meta(t.categoryLabel,
                                            Icons.bookmark_outline,
                                            color: categoryAccent(t)),
                                      if (t.actualSeconds > 0)
                                        meta(
                                            '${(t.actualSeconds / 60).toStringAsFixed(1)} / ${t.minutes} min',
                                            Icons.timelapse,
                                            color: sage),
                                      for (final f in t.fields
                                          .take(s.density == 'Compact' ? 1 : 3))
                                        meta('${f.name}: ${f.display}',
                                            Icons.tune,
                                            color: violet),
                                      if (t.scheduled != null)
                                        meta(
                                            t.scheduled!.isBefore(day(now))
                                                ? dateLabel(t.scheduled!)
                                                : dayKey(t.scheduled!) ==
                                                        dayKey(now)
                                                    ? t.scheduled!.hour == 0
                                                        ? 'Today'
                                                        : timeLabel(
                                                            t.scheduled!)
                                                    : dateLabel(t.scheduled!),
                                            Icons.calendar_today_outlined,
                                            color:
                                                t.scheduled!.isBefore(day(now))
                                                    ? accent
                                                    : sage),
                                      if (t.recurrence.isNotEmpty ||
                                          t.category == Category.habit)
                                        meta(
                                            t.recurrence.isEmpty
                                                ? 'daily'
                                                : t.recurrence,
                                            Icons.repeat_rounded,
                                            color: sage),
                                      if (subs.isNotEmpty)
                                        meta(
                                            '${subs.where((t) => t.done(now)).length}/${subs.length}',
                                            Icons.account_tree_outlined),
                                      if (t.comments.isNotEmpty)
                                        meta('${t.comments.length}',
                                            Icons.chat_bubble_outline_rounded),
                                      if (t.reminder != null)
                                        meta(timeLabel(t.reminder!),
                                            Icons.notifications_none_rounded),
                                      for (final l in t.labels.take(2))
                                        meta(l, Icons.sell_outlined,
                                            color: violet),
                                      if (t.deadline != null)
                                        meta(
                                            'Deadline ${dateLabel(t.deadline!)}',
                                            Icons.flag_outlined,
                                            color: accent)
                                    ]),
                                if (!nested && projectId == null) ...[
                                  const SizedBox(height: 7),
                                  Row(children: [
                                    Icon(
                                        p == null
                                            ? Icons.inbox_outlined
                                            : Icons.tag,
                                        size: 12,
                                        color: p == null
                                            ? secondary(context)
                                            : Color(p.color)),
                                    const SizedBox(width: 4),
                                    Flexible(
                                        child: Text(p?.name ?? 'Inbox',
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: secondary(context),
                                                fontSize: 10)))
                                  ])
                                ]
                              ])),
                          GritMenuButton<String>(
                              tooltip: 'Actions for ${t.title}',
                              icon: Icon(Icons.more_horiz,
                                  size: 18, color: secondary(context)),
                              onSelected: (v) => taskAction(t, v),
                              itemBuilder: (c) => [
                                    const PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Edit task')),
                                    const PopupMenuItem(
                                        value: 'today',
                                        child: Text('Schedule for today')),
                                    const PopupMenuItem(
                                        value: 'tomorrow',
                                        child: Text('Schedule for tomorrow')),
                                    const PopupMenuItem(
                                        value: 'focus',
                                        child: Text('Start focus session')),
                                    const PopupMenuItem(
                                        value: 'move',
                                        child: Text('Move to project')),
                                    const PopupMenuItem(
                                        value: 'duplicate',
                                        child: Text('Duplicate')),
                                    PopupMenuItem(
                                        value: t.trashed ? 'restore' : 'trash',
                                        child: Text(t.trashed
                                            ? 'Restore task'
                                            : 'Move to trash'))
                                  ])
                        ])))));
  }

  Widget meta(String text, IconData icon, {Color? color}) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color ?? secondary(context)),
        const SizedBox(width: 4),
        Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: compactPlatform(context) ? 12 : 11,
                    color: color == null
                        ? secondary(context)
                        : legibleColor(context, color))))
      ]);
  Future<void> completeTask(Task t) async {
    if (datedView &&
        t.category == Category.habit &&
        day(calendarDate) != day(DateTime.now())) {
      toast('Daily habits can be checked off on their day.');
      return;
    }
    if (completingTasks.contains(t.id)) return;
    final wasDone = t.done(DateTime.now());
    HapticFeedback.lightImpact();
    if (!wasDone && !MediaQuery.disableAnimationsOf(context)) {
      setState(() => completingTasks.add(t.id));
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (!mounted) return;
      completingTasks.remove(t.id);
    }
    final current = s.tasks.where((item) => item.id == t.id).firstOrNull;
    if (current == null || current.done(DateTime.now()) != wasDone) return;
    s.toggle(current);
    toast(
        t.recurrence.isNotEmpty && t.category != Category.habit
            ? 'Completed. Next occurrence scheduled.'
            : t.done(DateTime.now())
                ? s.gamification
                    ? 'A little more done. Nice work.'
                    : 'Task completed'
                : 'Task reopened',
        undo: true);
  }

  void taskAction(Task t, String action) {
    switch (action) {
      case 'edit':
        taskEditor(t);
      case 'today':
        s.schedule(t, day(DateTime.now()));
      case 'tomorrow':
        s.schedule(t, day(DateTime.now()).add(const Duration(days: 1)));
      case 'focus':
        focus(t);
      case 'duplicate':
        s.duplicate(t);
        toast('Task duplicated', undo: true);
      case 'move':
        moveDialog(t);
      case 'trash':
        s.deleteTask(t);
        toast('Moved to trash', undo: true);
      case 'restore':
        s.restoreTask(t);
        toast('Task restored');
    }
  }

  Widget addRow({String? section}) => InkWell(
      onTap: () => taskEditor(null, section: section),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 5),
          child: Row(children: [
            const Icon(Icons.add_rounded, size: 20, color: accent),
            const SizedBox(width: 12),
            Expanded(
                child: Text('Add task',
                    style: TextStyle(fontSize: 13, color: secondary(context)))),
            if (MediaQuery.sizeOf(context).width > 700) keycap('⌘ N')
          ])));
  Widget emptyState(String title, String subtitle,
          {String? actionLabel,
          VoidCallback? onAction,
          IconData icon = Icons.spa_outlined}) =>
      GritEmptyState(
          title: title,
          message: subtitle,
          actionLabel: actionLabel,
          onAction: onAction,
          icon: icon);
  Widget bulkToolbar() => Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: accent.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(10)),
      child: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('${selected.length} selected',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            TextButton(
                onPressed: () {
                  s.completeMany(selected);
                  setState(() {
                    selected.clear();
                    selectMode = false;
                  });
                },
                child: const Text('Complete')),
            TextButton(
                onPressed: () {
                  s.checkpoint();
                  for (final t
                      in s.tasks.where((t) => selected.contains(t.id))) {
                    t.scheduled =
                        day(DateTime.now()).add(const Duration(days: 1));
                  }
                  s.save();
                  setState(() => selected.clear());
                },
                child: const Text('Tomorrow')),
            TextButton(
                onPressed: () {
                  s.checkpoint();
                  for (final t
                      in s.tasks.where((t) => selected.contains(t.id))) {
                    t.trashed = true;
                    for (final child in s.descendants(t.id)) {
                      child.trashed = true;
                    }
                  }
                  s.save();
                  setState(() => selected.clear());
                  toast('Tasks moved to trash', undo: true);
                },
                child: const Text('Delete')),
            IconButton(
                tooltip: 'Exit selection',
                onPressed: () => setState(() {
                      selectMode = false;
                      selected.clear();
                    }),
                icon: const Icon(Icons.close, size: 16))
          ]));
  Widget boardView(List<Task> list) {
    final p = s.project(projectId);
    final columns =
        p?.sections ?? ['Priority 1', 'Priority 2', 'Priority 3', 'Priority 4'];
    final names = [if (p != null) 'Unsectioned', ...columns];
    return SizedBox(
        height: 560,
        child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: names.length,
            separatorBuilder: (c, i) => const SizedBox(width: 16),
            itemBuilder: (c, i) {
              final name = names[i];
              final group = list
                  .where((t) => p == null
                      ? t.priority == i + 1
                      : name == 'Unsectioned'
                          ? t.section.isEmpty || !columns.contains(t.section)
                          : t.section == name)
                  .toList();
              return DragTarget<Task>(
                  key: ValueKey('board-column-$name'),
                  onAcceptWithDetails: (d) {
                    HapticFeedback.lightImpact();
                    if (p == null) {
                      d.data.priority = i + 1;
                      s.save();
                    } else {
                      s.move(d.data, p.id, name == 'Unsectioned' ? '' : name);
                    }
                  },
                  builder: (c, candidate, rejected) => Container(
                      width: 270,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: candidate.isNotEmpty
                              ? accent.withValues(alpha: .07)
                              : subtle(c),
                          borderRadius: BorderRadius.circular(14)),
                      child: Column(children: [
                        groupHeader(name, group.length),
                        const SizedBox(height: 6),
                        Expanded(
                            child: ListView(children: [
                          for (final t in group)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: LongPressDraggable<Task>(
                                    key: ValueKey('board-task-${t.id}'),
                                    onDragStarted: () =>
                                        HapticFeedback.selectionClick(),
                                    onDragCompleted: () =>
                                        HapticFeedback.lightImpact(),
                                    data: t,
                                    childWhenDragging: Opacity(
                                        opacity: .3,
                                        child: taskRow(t, card: true)),
                                    feedback: Material(
                                        elevation: 4,
                                        borderRadius: BorderRadius.circular(12),
                                        child: SizedBox(
                                            width: 240,
                                            child: Padding(
                                                padding:
                                                    const EdgeInsets.all(18),
                                                child: Text(t.title)))),
                                    child: taskRow(t, card: true))),
                          addRow(section: p == null ? null : name)
                        ]))
                      ])));
            }));
  }

  Widget scheduleView(List<Task> list) {
    final blocks = list
        .where((t) =>
            t.blockStart != null &&
            dayKey(t.blockStart!) == dayKey(calendarDate))
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text(dayKey(calendarDate),
                style: const TextStyle(fontWeight: FontWeight.w600))),
        IconButton(
            tooltip: 'Previous day',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => calendarDate = DateTime(
                calendarDate.year, calendarDate.month, calendarDate.day - 1))),
        TextButton(
            onPressed: () => setState(() => calendarDate = day(DateTime.now())),
            child: const Text('Go to today')),
        IconButton(
            tooltip: 'Next day',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() => calendarDate = DateTime(
                calendarDate.year, calendarDate.month, calendarDate.day + 1))),
      ]),
      Text(
          'Drag onto an hour with a mouse. On touch, hold then drag. Tap a task to choose a time.',
          style: TextStyle(fontSize: 12, color: secondary(context))),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in list.where((t) =>
            (t.blockStart == null || day(t.blockStart!) != calendarDate) &&
            !t.done(calendarDate)))
          ScheduleTaskDrag<Task>(
              key: ValueKey('schedule-task-${t.id}'),
              onStart: () {
                HapticFeedback.selectionClick();
                setState(() => scheduleDragging = true);
              },
              onEnd: () => setState(() => scheduleDragging = false),
              data: t,
              feedback: Material(
                  color: Colors.transparent, child: Chip(label: Text(t.title))),
              child: ActionChip(
                  label: Text(t.title, overflow: TextOverflow.ellipsis),
                  onPressed: () => blockTask(t, date: calendarDate))),
      ]),
      const SizedBox(height: 16),
      SizedBox(
          height: 24 * 60,
          child: Stack(children: [
            for (var hour = 0; hour < 24; hour++)
              Positioned(
                top: hour * 60,
                left: 0,
                right: 0,
                height: 60,
                child: DragTarget<Task>(
                    key: ValueKey('schedule-hour-$hour'),
                    onAcceptWithDetails: (details) {
                      try {
                        s.timeBlock(
                            details.data,
                            DateTime(calendarDate.year, calendarDate.month,
                                calendarDate.day, hour));
                        HapticFeedback.lightImpact();
                        setState(() {});
                        toast(
                            'Scheduled at ${hour.toString().padLeft(2, '0')}:00',
                            undo: true);
                      } on FormatException catch (e) {
                        toast(e.message);
                      }
                    },
                    builder: (c, candidates, rejected) => Container(
                        decoration: BoxDecoration(
                            color: candidates.isEmpty
                                ? Colors.transparent
                                : accent.withValues(alpha: .08),
                            border:
                                Border(top: BorderSide(color: hairline(c)))),
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('${hour.toString().padLeft(2, '0')}:00',
                            style:
                                TextStyle(fontSize: 11, color: secondary(c))))),
              ),
            for (final t in blocks)
              Positioned(
                  top: (t.blockStart!.hour * 60 + t.blockStart!.minute)
                      .toDouble(),
                  left: 52,
                  right: 0,
                  height: min(
                      max(t.minutes.toDouble(), 32),
                      (1440 - t.blockStart!.hour * 60 - t.blockStart!.minute)
                          .toDouble()),
                  child: IgnorePointer(
                      ignoring: scheduleDragging,
                      child: ScheduleTaskDrag<Task>(
                          key: ValueKey('schedule-block-${t.id}'),
                          data: t,
                          onStart: () {
                            HapticFeedback.selectionClick();
                            setState(() => scheduleDragging = true);
                          },
                          onEnd: () => setState(() => scheduleDragging = false),
                          feedback: Material(
                              color: Colors.transparent,
                              child: Chip(label: Text(t.title))),
                          child: InkWell(
                              onTap: () => taskDetail(t),
                              child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                      color: sage.withValues(alpha: .16),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: sage.withValues(alpha: .4))),
                                  child: Text('${t.title} · ${t.minutes} min',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600))))))),
          ])),
    ]);
  }

  Widget calendarView(List<Task> list) {
    final first = DateTime(calendarDate.year, calendarDate.month, 1);
    final start = first.subtract(Duration(days: first.weekday - 1));
    final agenda = planningDayTasks(list, calendarDate,
        now: DateTime.now(), includeCompleted: completed);
    final unscheduled = list.where((t) => t.scheduled == null).toList();
    return Column(children: [
      Row(children: [
        Expanded(
            child: Text('${monthName(calendarDate.month)} ${calendarDate.year}',
                style: const TextStyle(fontWeight: FontWeight.w600))),
        IconButton(
            tooltip: 'Previous month',
            onPressed: () => setState(() => calendarDate =
                DateTime(calendarDate.year, calendarDate.month - 1, 1)),
            icon: const Icon(Icons.chevron_left, size: 20)),
        TextButton(
            onPressed: () => setState(() => calendarDate = day(DateTime.now())),
            child: const Text('Go to today')),
        IconButton(
            tooltip: 'Next month',
            onPressed: () => setState(() => calendarDate =
                DateTime(calendarDate.year, calendarDate.month + 1, 1)),
            icon: const Icon(Icons.chevron_right, size: 20))
      ]),
      const SizedBox(height: 12),
      DragTarget<Task>(
        key: const ValueKey('calendar-unscheduled'),
        onAcceptWithDetails: (details) {
          HapticFeedback.lightImpact();
          s.schedule(details.data, null);
        },
        builder: (c, candidates, rejected) => Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: candidates.isEmpty
                    ? subtle(c)
                    : accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: hairline(c))),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Unscheduled · ${unscheduled.length}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                  'Long-press a task and drag it onto a date. Drop here to remove its date.',
                  style: TextStyle(fontSize: 12, color: secondary(c))),
              if (unscheduled.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final t in unscheduled)
                    LongPressDraggable<Task>(
                        key: ValueKey('calendar-task-${t.id}'),
                        data: t,
                        onDragStarted: () => HapticFeedback.selectionClick(),
                        feedback: Material(
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Text(t.title))),
                        childWhenDragging: Opacity(
                            opacity: .3, child: Chip(label: Text(t.title))),
                        child: ActionChip(
                            label: Text(t.title),
                            onPressed: () => taskDetail(t))),
                ]),
              ],
            ])),
      ),
      Row(children: [
        for (final d in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
          Expanded(
              child: Center(
                  child: Text(d,
                      style:
                          TextStyle(color: secondary(context), fontSize: 10))))
      ]),
      const SizedBox(height: 10),
      GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: max(compactPlatform(context) ? 48 : 64,
                  MediaQuery.textScalerOf(context).scale(12) + 20),
              crossAxisSpacing: 3,
              mainAxisSpacing: 3),
          itemCount: 42,
          itemBuilder: (c, i) {
            final d = DateTime(start.year, start.month, start.day + i);
            final count = planningDayTasks(list, d,
                    now: DateTime.now(), includeCompleted: completed)
                .length;
            final selected = dayKey(d) == dayKey(calendarDate);
            return DragTarget<Task>(
                key: ValueKey('calendar-day-${dayKey(d)}'),
                onAcceptWithDetails: (details) {
                  final old = details.data.scheduled;
                  HapticFeedback.lightImpact();
                  s.schedule(
                      details.data,
                      DateTime(d.year, d.month, d.day, old?.hour ?? 0,
                          old?.minute ?? 0));
                  setState(() => calendarDate = d);
                },
                builder: (c, candidates, rejected) => InkWell(
                    onTap: () => setState(() => calendarDate = d),
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                        decoration: BoxDecoration(
                            color: selected
                                ? accent
                                : candidates.isNotEmpty
                                    ? accent.withValues(alpha: .15)
                                    : subtle(c),
                            borderRadius: BorderRadius.circular(9)),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('${d.day}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                      color: selected
                                          ? Colors.white
                                          : d.month != calendarDate.month
                                              ? secondary(c)
                                              : null)),
                              const SizedBox(height: 4),
                              Container(
                                  width: count > 0 ? 5 : 0,
                                  height: 5,
                                  decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: selected ? Colors.white : sage))
                            ]))));
          }),
      const SizedBox(height: 25),
      groupHeader(
          '${weekdayName(calendarDate.weekday)} · ${dateLabel(calendarDate)}',
          agenda.length),
      if (agenda.isEmpty)
        emptyState('Space in your day.',
            'Add a task for this date, or move one from another day.',
            actionLabel: 'Add a task for this day',
            onAction: () => taskEditor(null, date: calendarDate),
            icon: Icons.calendar_today_outlined),
      for (final t in agenda)
        LongPressDraggable<Task>(
            key: ValueKey('calendar-task-${t.id}'),
            onDragStarted: () => HapticFeedback.selectionClick(),
            onDragCompleted: () => HapticFeedback.lightImpact(),
            data: t,
            childWhenDragging:
                Opacity(opacity: .3, child: _taskRow(t, card: true)),
            feedback: Material(
                child: Padding(
                    padding: const EdgeInsets.all(15), child: Text(t.title))),
            child: _taskRow(t, card: true)),
      TextButton.icon(
          onPressed: () => taskEditor(null, date: calendarDate),
          icon: const Icon(Icons.add, size: 17),
          label: const Text('Add to this day'))
    ]);
  }

  Future<void> taskEditor(Task? existing,
      {String? section,
      Category? category,
      DateTime? date,
      Task? parent,
      String? initialText}) async {
    Widget builder(BuildContext c) => TaskEditor(
        store: s,
        task: existing,
        initialText: initialText,
        initialCategory: category,
        projectId: parent?.projectId ?? projectId,
        section: parent?.section ?? section,
        parentId: parent?.id,
        date: date ??
            (datedView
                ? calendarDate
                : view == 'Today'
                    ? day(DateTime.now())
                    : null));
    if (compactPlatform(context)) {
      await gritSheet<void>(context, builder);
    } else {
      await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          builder: builder);
    }
  }

  void taskDetail(Task task) {
    showGritDetails(
        context: context,
        builder: (c) => TaskDetailShell(
            completed: task.done(DateTime.now()),
            onEdit: () => taskEditor(task),
            onClose: () => Navigator.pop(c),
            onComplete: () {
              completeTask(task);
              Navigator.pop(c);
            },
            onFocus: () => focus(task),
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListenableBuilder(
                    listenable: s,
                    builder: (c, _) => SingleChildScrollView(
                        padding: EdgeInsets.all(compactPlatform(c) ? 20 : 25),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!compactPlatform(c))
                                Row(children: [
                                  Icon(
                                      task.projectId == null
                                          ? Icons.inbox_outlined
                                          : Icons.tag,
                                      size: 17,
                                      color: secondary(c)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(
                                          '${s.projectName(task)}${task.section.isEmpty ? '' : ' / ${task.section}'}',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: secondary(c)))),
                                  IconButton(
                                      tooltip: 'Edit task',
                                      onPressed: () => taskEditor(task),
                                      icon: const Icon(Icons.edit_outlined,
                                          size: 19)),
                                  IconButton(
                                      tooltip: 'Close details',
                                      onPressed: () => Navigator.pop(c),
                                      icon: const Icon(Icons.close, size: 20))
                                ]),
                              if (!compactPlatform(c))
                                const Divider(height: 30),
                              if (compactPlatform(c)) ...[
                                Text(s.projectName(task),
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: secondary(c))),
                                const SizedBox(height: 12),
                              ],
                              Text(task.title,
                                  style: TextStyle(
                                      fontSize: compactPlatform(c) ? 28 : 25,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -.6)),
                              const SizedBox(height: 16),
                              DetailGroup(
                                  child: Wrap(
                                      spacing: 8,
                                      runSpacing: 9,
                                      children: [
                                    Pill('Priority ${task.priority}',
                                        color: priorityColor(task.priority),
                                        onTap: () => chooseTaskPriority(task),
                                        icon: Icons.flag_outlined),
                                    if (task.scheduled != null)
                                      Pill(
                                          '${dateLabel(task.scheduled!)}${task.scheduled!.hour == 0 ? '' : ' · ${timeLabel(task.scheduled!)}'}',
                                          color: sage,
                                          onTap: () => scheduleActions(task),
                                          icon: Icons.calendar_today_outlined),
                                    if (task.scheduled == null)
                                      Pill('Schedule',
                                          color: sage,
                                          onTap: () => scheduleActions(task),
                                          icon: CupertinoIcons.calendar),
                                    Pill('${task.minutes} min',
                                        onTap: () => taskEditor(task),
                                        color: violet,
                                        icon: Icons.schedule),
                                    if (task.recurrence.isNotEmpty)
                                      Pill(task.recurrence,
                                          color: sage, icon: Icons.repeat),
                                    if (task.deadline != null)
                                      Pill(
                                          'Deadline ${dateLabel(task.deadline!)}',
                                          icon: Icons.flag_outlined),
                                    ...task.labels.map((l) => Pill(l,
                                        color: violet,
                                        icon: Icons.sell_outlined))
                                  ])),
                              const SizedBox(height: 20),
                              if (task.notes.isNotEmpty)
                                SelectableText(task.notes,
                                    style: TextStyle(
                                        color: secondary(c),
                                        fontSize: 13,
                                        height: 1.7))
                              else
                                TextButton.icon(
                                    onPressed: () => taskEditor(task),
                                    icon: const Icon(Icons.notes, size: 16),
                                    label: const Text('Add a description')),
                              const SizedBox(height: 26),
                              DetailGroup(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    groupHeader(
                                        'Custom fields', task.fields.length),
                                    for (final field in task.fields)
                                      ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(field.name),
                                          subtitle: Text(
                                              '${field.type} · ${field.display}'),
                                          onTap: () =>
                                              editTaskField(task, field),
                                          trailing: IconButton(
                                              tooltip: 'Remove ${field.name}',
                                              icon: const Icon(Icons.close,
                                                  size: 18),
                                              onPressed: () {
                                                s.checkpoint();
                                                task.fields = task.fields
                                                    .where((f) => f != field)
                                                    .toList();
                                                s.save();
                                              })),
                                    TextButton.icon(
                                        onPressed: () =>
                                            editTaskField(task, null),
                                        icon: const Icon(Icons.add, size: 16),
                                        label: const Text('Add custom field')),
                                    Text(
                                        'Actual focus: ${(task.actualSeconds / 60).toStringAsFixed(1)} min · estimated ${task.minutes} min',
                                        style: TextStyle(
                                            fontSize: 12, color: secondary(c))),
                                  ])),
                              const SizedBox(height: 20),
                              groupHeader(
                                  'Subtasks',
                                  s.activeTasks
                                      .where((t) => t.parentId == task.id)
                                      .length),
                              for (final sub in s.activeTasks
                                  .where((t) => t.parentId == task.id))
                                taskRow(sub, nested: true),
                              TextButton.icon(
                                  onPressed: () =>
                                      taskEditor(null, parent: task),
                                  icon: const Icon(Icons.add, size: 17),
                                  label: const Text('Add subtask')),
                              const Divider(height: 35),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                OutlinedButton.icon(
                                    onPressed: () => blockTask(task),
                                    icon: const Icon(
                                        Icons.calendar_month_outlined,
                                        size: 16),
                                    label: Text(task.blockStart == null
                                        ? 'Schedule a time block'
                                        : '${timeLabel(task.blockStart!)} · ${task.minutes} min block')),
                                if (task.blockStart != null)
                                  TextButton(
                                      onPressed: () {
                                        s.checkpoint();
                                        task.blockStart = null;
                                        s.save();
                                      },
                                      child: const Text('Remove block')),
                                if (task.blockStart != null)
                                  OutlinedButton.icon(
                                      onPressed: () => exportCalendar([task]),
                                      icon: const Icon(
                                          Icons.file_download_outlined,
                                          size: 16),
                                      label:
                                          const Text('Export calendar event'))
                              ]),
                              const SizedBox(height: 18),
                              const Text('Files',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              for (final file in task.attachments)
                                ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading:
                                        const Icon(Icons.attach_file, size: 18),
                                    title: Text(file['name'],
                                        style: const TextStyle(fontSize: 12)),
                                    subtitle: Text(
                                        '${file['size']} bytes · stored in your workspace',
                                        style: const TextStyle(fontSize: 10)),
                                    onTap: () async {
                                      try {
                                        await downloadFile(
                                            file['name'],
                                            base64Decode(file['data']),
                                            file['mime'] ??
                                                'application/octet-stream');
                                      } catch (e) {
                                        toast('Could not save the file.');
                                      }
                                    },
                                    trailing: IconButton(
                                        tooltip: 'Remove attachment',
                                        icon: const Icon(Icons.close, size: 16),
                                        onPressed: () {
                                          s.checkpoint();
                                          task.attachments =
                                              List.of(task.attachments)
                                                ..remove(file);
                                          s.save();
                                        })),
                              TextButton.icon(
                                  onPressed: () async {
                                    try {
                                      final file = await pickAttachment();
                                      if (file == null) return;
                                      if (task.attachments.length >= 5 ||
                                          task.attachments.fold<int>(
                                                      0,
                                                      (sum, f) =>
                                                          sum +
                                                          (f['size'] as int)) +
                                                  (file['size'] as int) >
                                              2 * 1024 * 1024) {
                                        toast(
                                            'Maximum five files and 2 MB total per task.');
                                        return;
                                      }
                                      s.checkpoint();
                                      task.attachments = [
                                        ...task.attachments,
                                        file
                                      ];
                                      s.save();
                                    } catch (e) {
                                      toast(e is FormatException
                                          ? e.message
                                          : 'File picker is unavailable on this platform.');
                                    }
                                  },
                                  icon: const Icon(Icons.add, size: 16),
                                  label:
                                      const Text('Attach a file · up to 1 MB')),
                              const Divider(height: 30),
                              const Text('Comments & notes',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              const SizedBox(height: 15),
                              for (final comment in task.comments)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 18),
                                    child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          avatar(),
                                          const SizedBox(width: 12),
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Text(
                                                    '${comment['author']} · ${dateLabel(DateTime.parse(comment['at']))}',
                                                    style: TextStyle(
                                                        fontSize: 10,
                                                        color: secondary(c))),
                                                const SizedBox(height: 5),
                                                Text(comment['text'],
                                                    style: const TextStyle(
                                                        fontSize: 13))
                                              ]))
                                        ])),
                              TextField(
                                  decoration: const InputDecoration(
                                      hintText:
                                          'Add a note… press Enter to save',
                                      prefixIcon: Icon(
                                          Icons.chat_bubble_outline,
                                          size: 18)),
                                  onSubmitted: (text) {
                                    if (text.trim().isNotEmpty) {
                                      s.addComment(task, text.trim());
                                    }
                                  }),
                              const SizedBox(height: 25),
                              if (compactPlatform(c))
                                TextButton.icon(
                                    onPressed: () {
                                      s.deleteTask(task);
                                      Navigator.pop(c);
                                      toast('Moved to trash', undo: true);
                                    },
                                    icon: const Icon(CupertinoIcons.trash,
                                        size: 18),
                                    label: const Text('Move to Trash')),
                              if (!compactPlatform(c))
                                Wrap(spacing: 10, runSpacing: 10, children: [
                                  FilledButton.icon(
                                      onPressed: () {
                                        completeTask(task);
                                        Navigator.pop(c);
                                      },
                                      icon: Icon(
                                          task.done(DateTime.now())
                                              ? Icons.undo
                                              : Icons.check,
                                          size: 17),
                                      label: Text(task.done(DateTime.now())
                                          ? 'Reopen task'
                                          : 'Complete task')),
                                  OutlinedButton.icon(
                                      onPressed: () => focus(task),
                                      icon: const Icon(Icons.play_arrow,
                                          size: 18),
                                      label: const Text('Focus')),
                                  TextButton(
                                      onPressed: () {
                                        s.deleteTask(task);
                                        Navigator.pop(c);
                                        toast('Moved to trash', undo: true);
                                      },
                                      child: const Text('Delete'))
                                ])
                            ]))))));
  }

  Future<void> chooseTaskPriority(Task task) async {
    final value = await gritActions<int>(context, 'Priority', {
      1: 'Priority 1 · Urgent',
      2: 'Priority 2 · High',
      3: 'Priority 3 · Medium',
      4: 'Priority 4 · Normal',
    });
    if (!mounted || value == null) return;
    s.checkpoint();
    task.priority = value;
    task.importance = [5, 4, 3, 2][value - 1];
    HapticFeedback.selectionClick();
    s.save();
  }

  Future<void> projectEditor([Project? original]) async {
    final name = TextEditingController(text: original?.name),
        description = TextEditingController(text: original?.description);
    var color = original?.color ?? 0xFFDF7561;
    var favorite = original?.favorite ?? false;
    String? parentId = original?.parentId;
    String? error;
    await showDialog(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, u) => AlertDialog(
                    scrollable: true,
                    title: Text(original == null
                        ? 'A new place for your plans'
                        : 'Edit project'),
                    content: SizedBox(
                        width: 430,
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                  controller: name,
                                  autofocus: true,
                                  decoration: InputDecoration(
                                      labelText: 'Project name',
                                      errorText: error)),
                              const SizedBox(height: 16),
                              GritChoiceField<String>(
                                  initialValue: parentId ?? 'root',
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                      labelText: 'Parent project'),
                                  items: [
                                    const DropdownMenuItem(
                                        value: 'root',
                                        child: Text('No parent')),
                                    ...s.projects
                                        .where((p) =>
                                            !p.archived &&
                                            p.id != original?.id &&
                                            (original == null ||
                                                !s.isProjectDescendant(
                                                    p.id, original.id)))
                                        .map((p) => DropdownMenuItem(
                                            value: p.id, child: Text(p.name)))
                                  ],
                                  onChanged: (v) => u(
                                      () => parentId = v == 'root' ? null : v)),
                              const SizedBox(height: 16),
                              TextField(
                                  controller: description,
                                  decoration: const InputDecoration(
                                      labelText:
                                          'A little description (optional)'),
                                  maxLines: 2),
                              const SizedBox(height: 22),
                              const Text('Make it yours',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12)),
                              const SizedBox(height: 12),
                              Wrap(spacing: 12, runSpacing: 10, children: [
                                for (final value in [
                                  0xFFDF7561,
                                  0xFF748DB1,
                                  0xFF96A080,
                                  0xFFBA91B8,
                                  0xFFE8B35E,
                                  0xFF72A8A1
                                ])
                                  InkWell(
                                      onTap: () => u(() => color = value),
                                      borderRadius: BorderRadius.circular(20),
                                      child: CircleAvatar(
                                          radius: 16,
                                          backgroundColor: Color(value),
                                          child: value == color
                                              ? const Icon(Icons.check,
                                                  size: 17, color: Colors.white)
                                              : null))
                              ]),
                              const SizedBox(height: 15),
                              SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Add to favorites',
                                      style: TextStyle(fontSize: 13)),
                                  value: favorite,
                                  onChanged: (v) => u(() => favorite = v)),
                              if (original != null)
                                TextButton.icon(
                                    onPressed: () {
                                      original.archived = !original.archived;
                                      s.record(
                                          original.archived
                                              ? 'Archived project'
                                              : 'Restored project',
                                          original.name);
                                      s.save();
                                      Navigator.pop(c);
                                      navigate('Inbox');
                                    },
                                    icon: const Icon(Icons.archive_outlined,
                                        size: 17),
                                    label: Text(original.archived
                                        ? 'Restore project'
                                        : 'Archive project'))
                            ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () {
                            if (name.text.trim().isEmpty) {
                              u(() => error = 'Give your project a name.');
                              return;
                            }
                            s.checkpoint();
                            if (original == null) {
                              final p = Project(
                                  id: s.id(),
                                  name: name.text.trim(),
                                  parentId: parentId,
                                  order: s.projects.length,
                                  color: color,
                                  favorite: favorite,
                                  description: description.text.trim());
                              s.addProject(p);
                              navigate('Project', project: p.id);
                            } else {
                              original.name = name.text.trim();
                              original.parentId = parentId;
                              original.description = description.text.trim();
                              original.color = color;
                              original.favorite = favorite;
                              s.save();
                            }
                            Navigator.pop(c);
                          },
                          child: Text(original == null
                              ? 'Create project'
                              : 'Save changes'))
                    ])));
  }

  Future<void> sectionEditor(String oldName) async {
    final p = s.project(projectId);
    if (p == null) return;
    final controller = TextEditingController(text: oldName);
    String? error;
    await showDialog(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, u) => AlertDialog(
                    scrollable: true,
                    title: const Text('Edit section'),
                    content: TextField(
                        controller: controller,
                        decoration: InputDecoration(
                            labelText: 'Section name', errorText: error)),
                    actions: [
                      TextButton(
                          onPressed: () {
                            s.checkpoint();
                            p.sections = List.of(p.sections)..remove(oldName);
                            for (final t in s.tasks.where((t) =>
                                t.projectId == p.id && t.section == oldName)) {
                              t.section = '';
                            }
                            s.save();
                            Navigator.pop(c);
                            toast('Section removed. Tasks kept in the project.',
                                undo: true);
                          },
                          child: const Text('Remove section')),
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () {
                            final name = controller.text.trim();
                            if (name.isEmpty ||
                                (name != oldName &&
                                    p.sections.contains(name))) {
                              u(() => error =
                                  'Use a unique, nonempty section name.');
                              return;
                            }
                            s.checkpoint();
                            p.sections = p.sections
                                .map((n) => n == oldName ? name : n)
                                .toList();
                            for (final t in s.tasks.where((t) =>
                                t.projectId == p.id && t.section == oldName)) {
                              t.section = name;
                            }
                            s.save();
                            Navigator.pop(c);
                          },
                          child: const Text('Save'))
                    ])));
  }

  Future<void> addSection() async {
    final name = await askText('Add a section', 'Section name');
    if (name == null || name.trim().isEmpty) return;
    final p = s.project(projectId);
    if (p == null) return;
    if (p.sections.contains(name.trim())) {
      toast('That section already exists.');
      return;
    }
    p.sections = List.of(p.sections)..add(name.trim());
    s.save();
  }

  Future<String?> askText(String title, String hint,
      {String initial = '', int maxLines = 1}) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                scrollable: true,
                title: Text(title),
                content: SizedBox(
                    width: 420,
                    child: TextField(
                        controller: controller,
                        autofocus: true,
                        maxLines: maxLines,
                        decoration: InputDecoration(hintText: hint))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, controller.text),
                      child: const Text('Save'))
                ]));
  }

  Future<void> moveDialog(Task t) async {
    String? target = t.projectId;
    await showDialog(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, u) => AlertDialog(
                    title: const Text('Move to a project'),
                    content: GritChoiceField<String>(
                        initialValue: target ?? 'inbox',
                        items: [
                          const DropdownMenuItem(
                              value: 'inbox', child: Text('Inbox')),
                          ...s.projects.where((p) => !p.archived).map((p) =>
                              DropdownMenuItem(
                                  value: p.id, child: Text(p.name)))
                        ],
                        onChanged: (v) =>
                            u(() => target = v == 'inbox' ? null : v)),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () {
                            s.move(t, target, '');
                            Navigator.pop(c);
                            toast('Task moved', undo: true);
                          },
                          child: const Text('Move task'))
                    ])));
  }

  void openSearch() {
    var text = '';
    showDialog(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, u) => Dialog(
                insetPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 60),
                child: SizedBox(
                    width: 660,
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 650),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Padding(
                              padding: const EdgeInsets.all(18),
                              child: TextField(
                                  autofocus: true,
                                  onChanged: (v) => u(() => text = v),
                                  decoration: const InputDecoration(
                                      hintText:
                                          'Search tasks, projects, labels…',
                                      prefixIcon: Icon(Icons.search)))),
                          const Divider(height: 1),
                          Flexible(
                              child: ListView(
                                  shrinkWrap: true,
                                  padding: const EdgeInsets.all(18),
                                  children: [
                                if (text.isEmpty)
                                  Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Text(
                                          'Find a thought, a plan, or something you’ve already done.',
                                          style: TextStyle(
                                              color: secondary(c),
                                              fontSize: 13))),
                                if (text.isNotEmpty &&
                                    !s.projects.any((p) => p.name
                                        .toLowerCase()
                                        .contains(text.toLowerCase())) &&
                                    !s.activeTasks.any((t) =>
                                        '${t.title} ${t.notes} ${t.labels.join(' ')}'
                                            .toLowerCase()
                                            .contains(text.toLowerCase())))
                                  GritEmptyState(
                                      title: 'No matches yet.',
                                      message:
                                          'Try a shorter phrase, a project name, or a label. Your tasks are still here.',
                                      icon: Icons.search_rounded),
                                for (final p in s.projects.where((p) =>
                                    text.isNotEmpty &&
                                    p.name
                                        .toLowerCase()
                                        .contains(text.toLowerCase())))
                                  ListTile(
                                      leading: Icon(Icons.tag,
                                          color: Color(p.color)),
                                      title: Text(p.name),
                                      subtitle: const Text('Project'),
                                      onTap: () {
                                        Navigator.pop(c);
                                        navigate('Project', project: p.id);
                                      }),
                                for (final t in s.activeTasks
                                    .where((t) =>
                                        text.isNotEmpty &&
                                        '${t.title} ${t.notes} ${t.labels.join(' ')}'
                                            .toLowerCase()
                                            .contains(text.toLowerCase()))
                                    .take(30))
                                  ListTile(
                                      leading: Icon(
                                          t.done(DateTime.now())
                                              ? Icons.check_circle_outline
                                              : Icons.circle_outlined,
                                          size: 18,
                                          color: priorityColor(t.priority)),
                                      title: Text(t.title,
                                          style: const TextStyle(fontSize: 13)),
                                      subtitle: Text(s.projectName(t),
                                          style: const TextStyle(fontSize: 11)),
                                      onTap: () {
                                        Navigator.pop(c);
                                        taskDetail(t);
                                      })
                              ])),
                          Padding(
                              padding: const EdgeInsets.all(10),
                              child: TextButton(
                                  onPressed: () => Navigator.pop(c),
                                  child: const Text('Close search')))
                        ]))))));
  }

  Future<void> bulkImport() async {
    final raw = await askText('Capture a few things at once',
        'One task per line. Try “Read chapter 3 tomorrow p2 @study”.',
        maxLines: 8);
    if (raw == null) return;
    s.checkpoint();
    var n = 0;
    for (final row
        in raw.split('\n').where((r) => r.trim().isNotEmpty).take(200)) {
      final q = QuickCapture.parse(row, DateTime.now());
      if (q.title.isEmpty) continue;
      s.tasks.add(Task(
          id: '${s.id()}-${n++}',
          title: q.title,
          projectId: projectId,
          scheduled: q.date,
          priority: q.priority,
          labels: q.labels,
          recurrence: q.recurrence));
    }
    s.record('Imported', '$n tasks');
    s.save();
    toast('$n tasks added. Dates are ready to review.', undo: true);
  }

  Widget filtersPage() {
    final labels = s.activeTasks.expand((t) => t.labels).toSet().toList()
      ..sort();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      pageHeader(
          'Filters & labels', 'Different ways to look at the same big picture.',
          action: IconButton(
              tooltip: 'Add filter',
              onPressed: () => filterEditor(),
              icon: const Icon(Icons.add))),
      groupHeader('Your filters', s.filters.length),
      for (final f in s.filters)
        ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading:
                const Icon(Icons.filter_alt_outlined, color: accent, size: 20),
            title: Text(f.name, style: const TextStyle(fontSize: 14)),
            subtitle: Text(f.query,
                style: TextStyle(color: secondary(context), fontSize: 11)),
            onTap: () => navigate('Filter', withFilter: f.id),
            trailing: IconButton(
                tooltip: 'Edit ${f.name}',
                onPressed: () => filterEditor(f),
                icon: const Icon(Icons.more_horiz, size: 18))),
      TextButton.icon(
          onPressed: () => filterEditor(),
          icon: const Icon(Icons.add, size: 17),
          label: const Text('Add a filter')),
      const SizedBox(height: 25),
      groupHeader('Labels', labels.length, action: manageLabels),
      if (labels.isEmpty)
        Text('Add @labels when creating a task to find them here.',
            style: TextStyle(color: secondary(context), fontSize: 13)),
      Wrap(
          spacing: 10,
          runSpacing: 12,
          children: labels
              .map((l) => Pill(l,
                  icon: Icons.sell_outlined,
                  color: violet,
                  onTap: () => navigate('Label', withLabel: l)))
              .toList()),
      const SizedBox(height: 32),
      SoftCard(
          color: subtle(context),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('A view that thinks like you',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 9),
            Text(
                'Try “today & p1”, “@deep-work”, or “(today | overdue) & #University”. Combine conditions with &, |, ! and parentheses.',
                style: TextStyle(
                    color: secondary(context), fontSize: 12, height: 1.7)),
            const SizedBox(height: 14),
            const Pill('Your tasks. Your perspective.',
                icon: Icons.auto_awesome_outlined, color: sage)
          ]))
    ]);
  }

  Future<void> manageLabels() async {
    final labels = s.tasks.expand((t) => t.labels).toSet().toList()..sort();
    await showDialog(
        context: context,
        builder: (c) => AlertDialog(
                scrollable: true,
                title: const Text('Organize labels'),
                content: SizedBox(
                    width: 450,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final label in labels)
                        ListTile(
                            leading: const Icon(Icons.sell_outlined,
                                size: 17, color: violet),
                            title: Text(label),
                            trailing:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                  tooltip: 'Rename label',
                                  icon:
                                      const Icon(Icons.edit_outlined, size: 17),
                                  onPressed: () async {
                                    final name = await askText(
                                        'Rename label', 'Label name',
                                        initial: label);
                                    if (name == null || name.trim().isEmpty) {
                                      return;
                                    }
                                    s.checkpoint();
                                    for (final t in s.tasks) {
                                      t.labels = t.labels
                                          .map((l) =>
                                              l == label ? name.trim() : l)
                                          .toSet()
                                          .toList();
                                    }
                                    s.save();
                                    if (c.mounted) Navigator.pop(c);
                                    toast('Label renamed', undo: true);
                                  }),
                              IconButton(
                                  tooltip: 'Remove label',
                                  icon: const Icon(Icons.close, size: 17),
                                  onPressed: () {
                                    s.checkpoint();
                                    for (final t in s.tasks) {
                                      t.labels = t.labels
                                          .where((l) => l != label)
                                          .toList();
                                    }
                                    s.save();
                                    Navigator.pop(c);
                                    toast('Label removed from tasks',
                                        undo: true);
                                  })
                            ]))
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Done'))
                ]));
  }

  Future<void> filterEditor([SavedFilter? existing]) async {
    final name = TextEditingController(text: existing?.name),
        query = TextEditingController(text: existing?.query);
    String? error;
    var favorite = existing?.favorite ?? false;
    await showDialog(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, u) => AlertDialog(
                    scrollable: true,
                    title: Text(
                        existing == null ? 'A new perspective' : 'Edit filter'),
                    content: SizedBox(
                        width: 450,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          TextField(
                              controller: name,
                              decoration: const InputDecoration(
                                  labelText: 'Filter name')),
                          const SizedBox(height: 15),
                          TextField(
                              controller: query,
                              decoration: InputDecoration(
                                  labelText: 'Query',
                                  hintText: '(today | overdue) & p1',
                                  errorText: error)),
                          const SizedBox(height: 16),
                          SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Add to favorites'),
                              value: favorite,
                              onChanged: (v) => u(() => favorite = v)),
                          Text(
                              'Supported: today, tomorrow, overdue, 7 days, p1–p4, @label, #Project name, recurring, subtask, completed, no date, no deadline, search: words. Use &, |, ! and parentheses.',
                              style:
                                  TextStyle(color: secondary(c), fontSize: 11))
                        ])),
                    actions: [
                      if (existing != null)
                        TextButton(
                            onPressed: () {
                              s.filters.remove(existing);
                              s.save();
                              Navigator.pop(c);
                            },
                            child: const Text('Delete')),
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () {
                            try {
                              if (name.text.trim().isEmpty ||
                                  query.text.trim().isEmpty) {
                                throw const FormatException(
                                    'Add a name and a query.');
                              }
                              TaskQuery.matches(Task(id: 'validate', title: ''),
                                  query.text, DateTime.now());
                              if (existing != null) {
                                existing.name = name.text.trim();
                                existing.query = query.text.trim();
                                existing.favorite = favorite;
                              } else {
                                s.filters.add(SavedFilter(
                                    s.id(), name.text.trim(), query.text.trim(),
                                    favorite: favorite));
                              }
                              s.save();
                              Navigator.pop(c);
                            } on FormatException catch (e) {
                              u(() => error = e.message);
                            }
                          },
                          child: const Text('Save filter'))
                    ])));
  }

  void templates() {
    final templates = <String, List<String>>{
      'A calmer study week': [
        'Collect this week’s assignments',
        'Choose one subject to review today',
        'Make a revision plan',
        'Practice a past paper',
        'Reflect on what worked'
      ],
      'Build a portfolio': [
        'Define the audience',
        'Choose three projects',
        'Write the project stories',
        'Design the home page',
        'Check mobile layouts',
        'Publish and share'
      ],
      'A weekly reset': [
        'Clear the inbox',
        'Review last week',
        'Choose three priorities',
        'Make space in the calendar',
        'Plan something to look forward to'
      ],
      'Start a reading habit': [
        'Choose your next book',
        'Set aside 15 minutes every day',
        'Write down one useful idea',
        'Share a recommendation'
      ]
    };
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
                scrollable: true,
                title: const Text('A good place to start'),
                content: SizedBox(
                    width: 580,
                    child: Column(children: [
                      Text('Pick a small framework. Make it your own.',
                          style: TextStyle(color: secondary(c))),
                      const SizedBox(height: 20),
                      for (final entry in templates.entries)
                        ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 8),
                            leading: const Icon(Icons.auto_awesome_outlined,
                                color: sage),
                            title: Text(entry.key,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: Text(
                                '${entry.value.length} thoughtful starting points',
                                style: const TextStyle(fontSize: 11)),
                            trailing: const Icon(Icons.arrow_forward_rounded,
                                size: 18),
                            onTap: () {
                              final p = Project(
                                  id: s.id(),
                                  name: entry.key,
                                  color: 0xFF96A080);
                              s.checkpoint();
                              s.projects.add(p);
                              for (var i = 0; i < entry.value.length; i++) {
                                s.tasks.add(Task(
                                    id: '${s.id()}-$i',
                                    title: entry.value[i],
                                    projectId: p.id,
                                    section: 'To do',
                                    category: Category.personalProject));
                              }
                              s.record('Used template', p.name);
                              s.save();
                              Navigator.pop(c);
                              navigate('Project', project: p.id);
                            })
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Close'))
                ]));
  }

  Widget productivity() {
    final now = DateTime.now();
    final counts = List.generate(
        7, (i) => s.completedOn(day(now).subtract(Duration(days: 6 - i))));
    final total = counts.fold(0, (a, b) => a + b);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      pageHeader('Your progress', 'Quiet effort. Visible progress.'),
      Wrap(spacing: 16, runSpacing: 16, children: [
        metric('Today', '${s.completedOn(now)}',
            'of ${s.dailyGoal} daily tasks', sage),
        metric(
            'Last 7 days', '$total', 'of ${s.weeklyGoal} weekly tasks', violet),
        if (s.gamification)
          metric(
              'Goal streak', '${s.goalStreak}', 'consecutive goal days', sage),
        if (s.gamification)
          metric('Experience', '${s.xp}', 'Level ${s.xp ~/ 500 + 1}', accent)
      ]),
      const SizedBox(height: 25),
      SoftCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('A week of small wins',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
        const SizedBox(height: 6),
        Text('Every day doesn’t have to look the same.',
            style: TextStyle(color: secondary(context), fontSize: 12)),
        const SizedBox(height: 30),
        SizedBox(
            height: 190,
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(7, (i) {
                  final d = day(now).subtract(Duration(days: 6 - i));
                  return Expanded(
                      child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text('${counts[i]}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: secondary(context))),
                                const SizedBox(height: 8),
                                AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    height: 10 +
                                        counts[i] /
                                            max(1, counts.reduce(max)) *
                                            100,
                                    decoration: BoxDecoration(
                                        color: i == 6
                                            ? accent
                                            : accent.withValues(alpha: .22),
                                        borderRadius:
                                            BorderRadius.circular(7))),
                                const SizedBox(height: 12),
                                Text(weekdayName(d.weekday).substring(0, 3),
                                    style: TextStyle(
                                        color: secondary(context),
                                        fontSize: 10))
                              ])));
                })))
      ])),
      const SizedBox(height: 24),
      SoftCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('The bigger picture',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
        const SizedBox(height: 7),
        Text('Your last 12 weeks. More color, more things done.',
            style: TextStyle(color: secondary(context), fontSize: 12)),
        const SizedBox(height: 23),
        LayoutBuilder(
            builder: (c, b) => Wrap(
                spacing: 5,
                runSpacing: 5,
                children: List.generate(84, (i) {
                  final d = day(now).subtract(Duration(days: 83 - i));
                  final n = s.completedOn(d);
                  return Tooltip(
                      message: '${dateLabel(d)} · $n completed',
                      child: Container(
                          width: (b.maxWidth - 65) / 14,
                          height: 19,
                          decoration: BoxDecoration(
                              color: n == 0
                                  ? subtle(c)
                                  : sage.withValues(
                                      alpha: min(1, .25 + n * .18)),
                              borderRadius: BorderRadius.circular(4))));
                })))
      ])),
      const SizedBox(height: 24),
      groupHeader(
          'Project progress', s.projects.where((p) => !p.archived).length),
      for (final p in s.projects.where((p) => !p.archived))
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Builder(builder: (c) {
              final tasks = s.activeTasks
                  .where((t) => t.projectId == p.id && t.parentId == null)
                  .toList();
              final done = tasks.where((t) => t.done(now)).length;
              return Column(children: [
                Row(children: [
                  Icon(Icons.tag, color: Color(p.color), size: 17),
                  const SizedBox(width: 9),
                  Expanded(
                      child:
                          Text(p.name, style: const TextStyle(fontSize: 13))),
                  Text('$done / ${tasks.length}',
                      style: TextStyle(color: secondary(c), fontSize: 11))
                ]),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                    value: tasks.isEmpty ? 0 : done / tasks.length,
                    color: Color(p.color),
                    backgroundColor: subtle(c),
                    minHeight: 5,
                    borderRadius: BorderRadius.circular(5))
              ]);
            }))
    ]);
  }

  Widget metric(String title, String number, String subtitle, Color color) =>
      SizedBox(
          width: 210,
          child: SoftCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: TextStyle(color: secondary(context), fontSize: 12)),
                const SizedBox(height: 17),
                Text(number,
                    style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1.5,
                        color: color)),
                const SizedBox(height: 5),
                Text(subtitle,
                    style: TextStyle(color: secondary(context), fontSize: 11))
              ])));
  Widget habitsPage() {
    final habits =
        s.activeTasks.where((t) => t.category == Category.habit).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      pageHeader(
          'Daily rituals', 'Small things that make a difference over time.',
          action: IconButton(
              tooltip: 'Add habit',
              onPressed: () => taskEditor(null),
              icon: const Icon(Icons.add))),
      SoftCard(
          color: subtle(context),
          child: Row(children: [
            const Icon(Icons.ac_unit_rounded, color: violet, size: 23),
            const SizedBox(width: 15),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('A day off doesn’t erase your progress.',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 5),
                  Text('One streak freeze each week protects yesterday.',
                      style: TextStyle(color: secondary(context), fontSize: 11))
                ])),
            TextButton(
                onPressed: () => toast(s.freezeYesterday()
                    ? 'Yesterday’s streak is protected.'
                    : 'You’ve used this week’s freeze.'),
                child: const Text('Use freeze'))
          ])),
      const SizedBox(height: 25),
      if (habits.isEmpty)
        emptyState('Make a little time for yourself.',
            'Choose Habit when adding a task. Start with reading, movement, or a few minutes of practice.',
            actionLabel: 'Create a habit',
            onAction: () => taskEditor(null, category: Category.habit),
            icon: Icons.repeat_rounded),
      for (final t in habits)
        Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: SoftCard(
                padding: const EdgeInsets.fromLTRB(16, 5, 16, 16),
                child: Column(children: [
                  taskRow(t, card: true),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: Pill(
                            '${streak(t, DateTime.now(), freezes: s.freezes)} day streak',
                            color: sage,
                            icon: Icons.local_fire_department_outlined)),
                    const SizedBox(width: 8),
                    for (var i = 6; i >= 0; i--)
                      Padding(
                          padding: const EdgeInsets.only(left: 5),
                          child: Tooltip(
                              message: dateLabel(day(DateTime.now())
                                  .subtract(Duration(days: i))),
                              child: Container(
                                  width: 18,
                                  height: 22,
                                  decoration: BoxDecoration(
                                      color: t.history.contains(dayKey(
                                              day(DateTime.now())
                                                  .subtract(Duration(days: i))))
                                          ? sage
                                          : subtle(context),
                                      borderRadius: BorderRadius.circular(5)),
                                  child: t.history.contains(dayKey(day(DateTime.now()).subtract(Duration(days: i))))
                                      ? const Icon(Icons.check,
                                          size: 12, color: Colors.white)
                                      : null)))
                  ])
                ])))
    ]);
  }

  Widget eventsPage() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        pageHeader('Milestones', 'A big day feels smaller with a good plan.',
            action: IconButton(
                tooltip: 'Add event',
                onPressed: () => eventEditor(),
                icon: const Icon(Icons.add))),
        if (s.events.isEmpty)
          emptyState('Something to work towards.',
              'Give your next exam, interview, or submission a date. We’ll help you plan the steps leading up to it.',
              actionLabel: 'Add a milestone',
              onAction: () => eventEditor(),
              icon: Icons.flag_outlined),
        for (final e in s.events)
          Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: SoftCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      Pill(e.type, icon: Icons.flag_outlined, color: violet),
                      const Spacer(),
                      Text(
                          '${e.date.difference(day(DateTime.now())).inDays} days',
                          style: const TextStyle(
                              fontSize: 12,
                              color: accent,
                              fontWeight: FontWeight.w600)),
                      IconButton(
                          tooltip: 'Edit event',
                          onPressed: () => eventEditor(e),
                          icon: const Icon(Icons.more_horiz, size: 18))
                    ]),
                    const SizedBox(height: 12),
                    Text(e.title,
                        style: const TextStyle(
                            fontSize: 21, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 7),
                    Text('${dateLabel(e.date)}, ${e.date.year}',
                        style:
                            TextStyle(color: secondary(context), fontSize: 12)),
                    const SizedBox(height: 17),
                    for (final t
                        in s.activeTasks.where((t) => t.eventId == e.id))
                      taskRow(t),
                    TextButton.icon(
                        onPressed: () async {
                          final text = await askText('Add a preparation step',
                              'A small thing to do before the big day');
                          if (text == null || text.trim().isEmpty) return;
                          s.addTask(Task(
                              id: s.id(),
                              title: text.trim(),
                              eventId: e.id,
                              deadline: e.date,
                              category: Category.event));
                        },
                        icon: const Icon(Icons.add, size: 17),
                        label: const Text('Add a preparation step'))
                  ])))
      ]);
  Future<void> eventEditor([GritEvent? event]) async {
    final name = TextEditingController(text: event?.title);
    var type = event?.type ?? 'Exam';
    var date = event?.date ?? day(DateTime.now()).add(const Duration(days: 7));
    String? error;
    await showDialog(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, u) => AlertDialog(
                    scrollable: true,
                    title: Text(
                        event == null ? 'A new milestone' : 'Edit milestone'),
                    content: SizedBox(
                        width: 430,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          TextField(
                              controller: name,
                              decoration: InputDecoration(
                                  labelText: 'Name', errorText: error)),
                          const SizedBox(height: 15),
                          GritChoiceField<String>(
                              initialValue: type,
                              items: [
                                'Exam',
                                'Interview',
                                'Submission',
                                'Hackathon'
                              ]
                                  .map((v) => DropdownMenuItem(
                                      value: v, child: Text(v)))
                                  .toList(),
                              onChanged: (v) => type = v!),
                          const SizedBox(height: 15),
                          OutlinedButton.icon(
                              onPressed: () async {
                                final d = await showDatePicker(
                                    context: c,
                                    initialDate: date,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2050));
                                if (d != null) u(() => date = d);
                              },
                              icon: const Icon(Icons.calendar_today, size: 17),
                              label: Text('${dateLabel(date)}, ${date.year}'))
                        ])),
                    actions: [
                      if (event != null)
                        TextButton(
                            onPressed: () {
                              s.checkpoint();
                              s.events.remove(event);
                              for (final t in s.tasks
                                  .where((t) => t.eventId == event.id)) {
                                t.eventId = null;
                              }
                              s.save();
                              Navigator.pop(c);
                              toast('Milestone removed. Its tasks are kept.',
                                  undo: true);
                            },
                            child: const Text('Delete')),
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () {
                            if (name.text.trim().isEmpty) {
                              u(() => error = 'Add a name.');
                              return;
                            }
                            s.checkpoint();
                            if (event == null) {
                              s.events.add(GritEvent(
                                  s.id(), name.text.trim(), type, date));
                            } else {
                              event.title = name.text.trim();
                              event.type = type;
                              event.date = date;
                            }
                            s.save();
                            Navigator.pop(c);
                          },
                          child: const Text('Save milestone'))
                    ])));
  }

  Widget activityPage() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        pageHeader('Activity',
            'The story of your progress, one small action at a time.'),
        if (s.activity.isEmpty)
          emptyState('Your story starts here.',
              'Add, complete, or organize a task to see your progress here.',
              actionLabel: 'Go to Today',
              onAction: () => navigate('Today'),
              icon: Icons.history_rounded),
        for (final a in s.activity)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                        color: subtle(context),
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(
                        a['verb'].toString().startsWith('Completed')
                            ? Icons.check_rounded
                            : Icons.history,
                        size: 16,
                        color: sage)),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('${a['verb']} ${a['title']}',
                          style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(
                          '${dateLabel(DateTime.parse(a['at']))} · ${timeLabel(DateTime.parse(a['at']))}',
                          style: TextStyle(
                              color: secondary(context), fontSize: 10))
                    ]))
              ]))
      ]);
  Widget settingsPage() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        pageHeader('Make yourself at home',
            'The little details that make your space feel like yours.'),
        SoftCard(
            child: Column(children: [
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: avatar(),
              title: Text(s.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(s.user?.email ?? 'Local workspace',
                  style: TextStyle(color: secondary(context), fontSize: 12)),
              trailing: TextButton(
                  onPressed: () async {
                    final name = await askText(
                        'What should we call you?', 'Name',
                        initial: s.name);
                    if (name != null && name.trim().isNotEmpty) {
                      s.name = name.trim();
                      s.save();
                    }
                  },
                  child: const Text('Edit'))),
          const Divider(height: 30),
          GritChoiceField<String>(
              key: ValueKey('appearance-${s.appearance}'),
              initialValue: s.appearance,
              decoration: const InputDecoration(labelText: 'Appearance'),
              items: ['System', 'Light', 'Dark']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) {
                s.appearance = v!;
                s.darkMode = v == 'Dark';
                s.save();
              }),
          SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: s.oledBlack,
              title: const Text('Pure black'),
              subtitle:
                  const Text('Use an OLED black canvas in Dark appearance.'),
              onChanged: (v) {
                s.oledBlack = v;
                s.save();
              }),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Gamification'),
              subtitle: const Text(
                  'Show XP, levels, goal celebrations and streaks. Off by default.'),
              value: s.gamification,
              onChanged: (v) {
                s.gamification = v;
                s.save();
              }),
          GritChoiceField<String>(
              initialValue: s.density,
              decoration: const InputDecoration(labelText: 'Task density'),
              items: ['Compact', 'Comfortable', 'Spacious']
                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  .toList(),
              onChanged: (d) {
                s.density = d!;
                s.save();
              }),
          const SizedBox(height: 12),
          if (s.gamification)
            Row(children: [
              const Expanded(
                  child:
                      Text('Daily task goal', style: TextStyle(fontSize: 14))),
              IconButton(
                  tooltip: 'Decrease goal',
                  onPressed: s.dailyGoal > 1
                      ? () {
                          s.dailyGoal--;
                          s.save();
                        }
                      : null,
                  icon: const Icon(Icons.remove_circle_outline, size: 20)),
              Text('${s.dailyGoal}'),
              IconButton(
                  tooltip: 'Increase goal',
                  onPressed: s.dailyGoal < 30
                      ? () {
                          s.dailyGoal++;
                          s.save();
                        }
                      : null,
                  icon: const Icon(Icons.add_circle_outline, size: 20))
            ]),
          const SizedBox(height: 16),
          Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  'Daily study capacity · ${s.capacity ~/ 60}h ${s.capacity % 60}m',
                  style: const TextStyle(fontSize: 13))),
          Slider(
              value: s.capacity.toDouble().clamp(30, 480),
              min: 30,
              max: 480,
              divisions: 15,
              onChanged: (v) {
                s.capacity = v.round();
                s.save();
              }),
          if (s.gamification)
            Row(children: [
              const Expanded(
                  child: Text('Weekly completion goal',
                      style: TextStyle(fontSize: 13))),
              IconButton(
                  tooltip: 'Decrease weekly goal',
                  onPressed: s.weeklyGoal > 1
                      ? () {
                          s.weeklyGoal--;
                          s.save();
                        }
                      : null,
                  icon: const Icon(Icons.remove_circle_outline, size: 20)),
              Text('${s.weeklyGoal}'),
              IconButton(
                  tooltip: 'Increase weekly goal',
                  onPressed: s.weeklyGoal < 210
                      ? () {
                          s.weeklyGoal++;
                          s.save();
                        }
                      : null,
                  icon: const Icon(Icons.add_circle_outline, size: 20))
            ])
        ])),
        const SizedBox(height: 20),
        SoftCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Your data belongs to you',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Text(
              'Local work stays on this device. Create a backup before changing devices or clearing browser data.',
              style: TextStyle(color: secondary(context), fontSize: 12)),
          const SizedBox(height: 15),
          Wrap(spacing: 10, runSpacing: 10, children: [
            OutlinedButton.icon(
                onPressed: () => exportCalendar(s.activeTasks),
                icon: const Icon(Icons.calendar_month, size: 16),
                label: const Text('Export time blocks (.ics)')),
            OutlinedButton.icon(
                onPressed: exportBackup,
                icon: const Icon(Icons.ios_share, size: 16),
                label: const Text('Export backup')),
            OutlinedButton.icon(
                onPressed: restoreBackup,
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('Restore backup')),
            TextButton.icon(
                onPressed: () => navigate('Trash'),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Open trash'))
          ])
        ])),
        const SizedBox(height: 20),
        SoftCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Account & connections',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
          const SizedBox(height: 12),
          Text(
              s.user == null
                  ? 'Sign in when your Firebase service is configured. Your local workspace and cloud account are separate.'
                  : 'Connected as ${s.user?.email}',
              style: TextStyle(color: secondary(context), fontSize: 12)),
          const SizedBox(height: 15),
          if (s.user != null)
            OutlinedButton(onPressed: s.logout, child: const Text('Sign out'))
          else
            OutlinedButton(
                onPressed: account,
                child: Text(s.cloud
                    ? 'Sign in / create account'
                    : 'Cloud setup details')),
          if (s.user != null)
            TextButton.icon(
                icon: const Icon(Icons.security_outlined, size: 18),
                label: const Text('Sign out on every device'),
                onPressed: () async {
                  try {
                    await s.endAllSessions();
                    toast('All cloud sessions ended.');
                  } catch (_) {
                    toast(
                        'Requires the secure backend and a sign-in within the last 5 minutes. Your local tasks are kept.');
                  }
                }),
          const SizedBox(height: 20),
          const Divider(),
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.notifications_none_rounded, size: 21),
              title: const Text('Reminders', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                  'In-app reminders while this workspace is open',
                  style: TextStyle(fontSize: 11)),
              onTap: reminders),
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.extension_outlined, size: 21),
              title: const Text('Integrations & collaboration',
                  style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                  'Connection status and production requirements',
                  style: TextStyle(fontSize: 11)),
              onTap: connections)
        ])),
        const SizedBox(height: 20),
        if (s.projects.any((p) => p.archived))
          SoftCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Archived projects',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                for (final p in s.projects.where((p) => p.archived))
                  ListTile(
                      title: Text(p.name),
                      trailing: TextButton(
                          onPressed: () {
                            p.archived = false;
                            s.save();
                          },
                          child: const Text('Restore')))
              ])),
        const SizedBox(height: 25),
        if (hasAndroidBridge)
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
                onPressed: () async {
                  await platformBridge
                      .invokeMethod('enableQuickAddNotification');
                },
                icon: const Icon(Icons.notifications_outlined, size: 16),
                label: const Text('Enable quick-add notification')),
            TextButton(
                onPressed: () async {
                  await platformBridge
                      .invokeMethod('disableQuickAddNotification');
                },
                child: const Text('Disable'))
          ]),
        Text('GRIT · Personal workspace 0.5\nMade for a little more clarity.',
            style:
                TextStyle(color: secondary(context), fontSize: 11, height: 1.8))
      ]);
  void exportBackup() {
    final raw = const JsonEncoder.withIndent('  ').convert(s.toJson());
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
                scrollable: true,
                title: const Text('Your workspace backup'),
                content: SizedBox(
                    width: 550,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                          'Copy this JSON and save it in a private file. It includes your task notes and comments.',
                          style: TextStyle(color: secondary(c), fontSize: 12)),
                      const SizedBox(height: 16),
                      SizedBox(
                          height: 260,
                          child: SingleChildScrollView(
                              child: SelectableText(raw,
                                  style: const TextStyle(
                                      fontFamily: 'monospace', fontSize: 10))))
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Close')),
                  FilledButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: raw));
                        if (mounted) {
                          toast('Backup copied. Save it somewhere private.');
                        }
                      },
                      icon: const Icon(Icons.copy, size: 17),
                      label: const Text('Copy backup'))
                ]));
  }

  Future<void> restoreBackup() async {
    final raw = await askText('Restore a GRIT backup',
        'Paste your JSON backup. This replaces this workspace. You can undo immediately afterwards.',
        maxLines: 8);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      s.importBackup(raw);
      toast('Backup restored', undo: true);
    } catch (e) {
      toast('Could not restore: use a valid GRIT JSON backup.');
    }
  }

  void reminders() {
    final list = s.activeTasks
        .where((t) => t.reminder != null && !t.done(DateTime.now()))
        .toList()
      ..sort((a, b) => a.reminder!.compareTo(b.reminder!));
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
                scrollable: true,
                title: const Text('A helpful nudge'),
                content: SizedBox(
                    width: 470,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'These reminders appear while GRIT is open. Background push delivery is not connected in this build.',
                              style:
                                  TextStyle(color: secondary(c), fontSize: 12)),
                          const SizedBox(height: 20),
                          if (list.isEmpty)
                            GritEmptyState(
                                title: 'A nudge when you need it.',
                                message:
                                    'Choose a reminder in a task’s details. You’ll find your upcoming nudges here.',
                                icon: Icons.notifications_none_rounded,
                                actionLabel: 'Add a task with a reminder',
                                onAction: () {
                                  Navigator.pop(c);
                                  taskEditor(null);
                                }),
                          for (final t in list)
                            ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(t.title,
                                    style: const TextStyle(fontSize: 13)),
                                subtitle: Text(
                                    '${dateLabel(t.reminder!)} at ${timeLabel(t.reminder!)}',
                                    style: const TextStyle(fontSize: 11)),
                                onTap: () {
                                  Navigator.pop(c);
                                  taskDetail(t);
                                })
                        ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Done'))
                ]));
  }

  void connections() => showDialog(
      context: context,
      builder: (c) => AlertDialog(
              scrollable: true,
              title: const Text('Connected services'),
              content: const SizedBox(
                  width: 490,
                  child: Text(
                      'Your personal planning tools work locally. These services need a configured backend and are not active:\n\n• Shared projects, invitations, assignments and team roles\n• Google / Outlook calendar sync\n• Background push, email and Telegram reminders\n• File uploads and voice capture\n• AI coaching, voice-to-task and syllabus import\n• Play Store subscriptions\n\nNo invitations, uploads, AI calls, or purchases are sent from this workspace.',
                      style: TextStyle(fontSize: 13, height: 1.8))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('Close'))
              ]));
  void account() {
    if (!s.cloud) {
      showDialog(
          context: context,
          builder: (c) => AlertDialog(
                  title: const Text('Connect your own cloud'),
                  content: const Text(
                      'Cloud is off in this build. Configure your Firebase project, authentication providers and database rules using the included setup guide. Your local tasks remain available without an account.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('Got it'))
                  ]));
      return;
    }
    final email = TextEditingController(), password = TextEditingController();
    bool register = false, busy = false;
    String? error;
    showDialog(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, u) => AlertDialog(
                    scrollable: true,
                    title:
                        Text(register ? 'Create an account' : 'Welcome back'),
                    content: SizedBox(
                        width: 410,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          TextField(
                              controller: email,
                              decoration:
                                  const InputDecoration(labelText: 'Email'),
                              keyboardType: TextInputType.emailAddress),
                          const SizedBox(height: 16),
                          TextField(
                              controller: password,
                              obscureText: true,
                              decoration:
                                  const InputDecoration(labelText: 'Password')),
                          if (error != null)
                            Text(error!, style: const TextStyle(color: accent)),
                          TextButton(
                              onPressed: busy
                                  ? null
                                  : () => u(() => register = !register),
                              child: Text(register
                                  ? 'Already have an account?'
                                  : 'Create an account')),
                          OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      u(() => busy = true);
                                      try {
                                        await s.google();
                                        if (c.mounted) Navigator.pop(c);
                                      } catch (e) {
                                        if (c.mounted) {
                                          u(() {
                                            error =
                                                'Google sign-in failed. Check your provider configuration.';
                                            busy = false;
                                          });
                                        }
                                      }
                                    },
                              child: const Text('Continue with Google'))
                        ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  u(() => busy = true);
                                  try {
                                    await s.authenticate(
                                        email.text.trim(), password.text,
                                        register: register);
                                    if (c.mounted) Navigator.pop(c);
                                  } catch (e) {
                                    if (c.mounted) {
                                      u(() {
                                        error =
                                            'Check your details and connection, then try again.';
                                        busy = false;
                                      });
                                    }
                                  }
                                },
                          child: Text(busy
                              ? 'Connecting…'
                              : register
                                  ? 'Create account'
                                  : 'Sign in'))
                    ])));
  }

  Future<void> blockTask(Task t, {DateTime? date}) async {
    final pickedDate = await showDatePicker(
        context: context,
        initialDate: date ?? t.blockStart ?? t.scheduled ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2050));
    if (pickedDate == null || !mounted) return;
    final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(
            t.blockStart ?? DateTime(DateTime.now().year, 1, 1, 9)));
    if (time == null || !mounted) return;
    try {
      s.timeBlock(
          t,
          DateTime(pickedDate.year, pickedDate.month, pickedDate.day, time.hour,
              time.minute));
      toast('Time block saved', undo: true);
    } on FormatException catch (e) {
      toast(e.message);
    }
  }

  Future<void> exportCalendar(Iterable<Task> tasks) async {
    if (!tasks.any((t) => t.blockStart != null)) {
      toast('Schedule a time block first.');
      return;
    }
    try {
      await downloadFile(
          'grit-calendar.ics',
          Uint8List.fromList(utf8.encode(calendarExport(tasks))),
          'text/calendar');
    } catch (e) {
      toast('Could not export the calendar file.');
    }
  }

  Color categoryAccent(Task task) => [
        sage,
        violet,
        accent,
        const Color(0xFF6999AB),
        const Color(0xFFB69A61)
      ][task.category.index];
  Future<void> editTaskField(Task task, TaskField? old) async {
    final field = await showDialog<TaskField>(
        context: context,
        builder: (c) => TaskFieldEditor(
            initial: old,
            names: task.fields.where((f) => f != old).map((f) => f.name)));
    if (field == null || !mounted) return;
    s.checkpoint();
    task.fields = [
      for (final f in task.fields)
        if (f != old) f,
      field
    ];
    s.save();
  }

  void focus(Task t) => showDialog(
      context: context,
      builder: (c) =>
          FocusSession(task: t, store: s, onComplete: () => completeTask(t)));
}

class TaskEditor extends StatefulWidget {
  const TaskEditor(
      {super.key,
      required this.store,
      this.task,
      this.initialText,
      this.initialCategory,
      this.projectId,
      this.section,
      this.parentId,
      this.date});
  final GritStore store;
  final Task? task;
  final String? initialText;
  final Category? initialCategory;
  final String? projectId, section, parentId;
  final DateTime? date;
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  late TextEditingController title, notes, labels, customRule;
  late String? projectId;
  late String section, recurrence;
  late String categoryValue;
  late int priority, minutes;
  DateTime? scheduled, deadline, reminder;
  String? error;
  bool more = false, smart = true;
  int categoryRevision = 0, projectRevision = 0;
  @override
  void initState() {
    super.initState();
    final t = widget.task;
    title = TextEditingController(text: t?.title ?? widget.initialText);
    notes = TextEditingController(text: t?.notes);
    labels = TextEditingController(text: t?.labels.join(', '));
    projectId = t?.projectId ?? widget.projectId;
    section = t?.section ?? widget.section ?? '';
    categoryValue = t?.customCategory.isNotEmpty == true
        ? 'custom:${t!.customCategory}'
        : (t?.category ?? widget.initialCategory ?? Category.personalProject)
            .name;
    priority = t?.priority ?? 4;
    minutes = t?.minutes ?? 30;
    scheduled = t?.scheduled ?? widget.date;
    deadline = t?.deadline;
    reminder = t?.reminder;
    recurrence = t?.recurrence ?? '';
    customRule = TextEditingController(
        text: recurrence.contains('FREQ=')
            ? recurrence
            : 'FREQ=WEEKLY;BYDAY=MO,WE,FR');
    smart = t == null;
    more = t != null;
  }

  @override
  void dispose() {
    title.dispose();
    notes.dispose();
    labels.dispose();
    customRule.dispose();
    super.dispose();
  }

  Future<DateTime?> chooseDate(DateTime? initial,
      {bool withTime = true}) async {
    if (compactPlatform(context)) {
      return pickGritDate(context, initial ?? DateTime.now(),
          withTime: withTime);
    }
    final date = await showDatePicker(
        context: context,
        initialDate: initial ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2050));
    if (date == null || !mounted) return null;
    if (!withTime) return date;
    final time = await showTimePicker(
        context: context,
        initialTime: initial != null
            ? TimeOfDay.fromDateTime(initial)
            : const TimeOfDay(hour: 9, minute: 0));
    return time == null
        ? date
        : DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<String?> manageCustomCategories() async {
    final controller = TextEditingController();
    String? message;
    final selected = await ownedTextDialog<String>(
        context,
        controller,
        (dialogContext) => StatefulBuilder(
            builder: (dialogContext, update) => AlertDialog(
                  title: const Text('Your categories'),
                  content: SizedBox(
                      width: 420,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                            'Create categories such as Backend learning or Certification. They stay in this workspace and can be renamed later.',
                            style: TextStyle(
                                color: secondary(context), fontSize: 12)),
                        const SizedBox(height: 14),
                        if (widget.store.customCategories.isNotEmpty)
                          SizedBox(
                              height: 180,
                              child: ListView(
                                  shrinkWrap: true,
                                  children: widget.store.customCategories
                                      .map((name) => ListTile(
                                            dense: true,
                                            contentPadding: EdgeInsets.zero,
                                            leading: const Icon(
                                                Icons.bookmark_border,
                                                size: 18),
                                            title: Text(name),
                                            onTap: () => Navigator.pop(
                                                dialogContext, name),
                                            trailing: Wrap(children: [
                                              IconButton(
                                                  tooltip: 'Rename category',
                                                  icon: const Icon(
                                                      Icons.edit_outlined,
                                                      size: 17),
                                                  onPressed: () async {
                                                    final renamed =
                                                        await _renameCategory(
                                                            name);
                                                    if (renamed != null) {
                                                      update(() {});
                                                    }
                                                  }),
                                              IconButton(
                                                  tooltip: 'Remove category',
                                                  icon: const Icon(
                                                      Icons.delete_outline,
                                                      size: 17),
                                                  onPressed: () {
                                                    widget.store
                                                        .removeCustomCategory(
                                                            name);
                                                    update(() {});
                                                  })
                                            ]),
                                          ))
                                      .toList())),
                        TextField(
                            controller: controller,
                            autofocus: widget.store.customCategories.isEmpty,
                            decoration: InputDecoration(
                                labelText: 'New category name',
                                hintText: 'Backend learning',
                                errorText: message),
                            onSubmitted: (_) {
                              final value = controller.text.trim();
                              if (!widget.store.addCustomCategory(value)) {
                                update(() =>
                                    message = 'Use a unique category name.');
                              } else {
                                Navigator.pop(dialogContext, value);
                              }
                            }),
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Close')),
                    FilledButton(
                        onPressed: () {
                          final value = controller.text.trim();
                          if (!widget.store.addCustomCategory(value)) {
                            update(
                                () => message = 'Use a unique category name.');
                          } else {
                            Navigator.pop(dialogContext, value);
                          }
                        },
                        child: const Text('Add category'))
                  ],
                )));
    return selected;
  }

  Future<String?> _renameCategory(String oldName) async {
    final controller = TextEditingController(text: oldName);
    final value = await ownedTextDialog<String>(
        context,
        controller,
        (c) => AlertDialog(
              title: const Text('Rename category'),
              content: TextField(controller: controller, autofocus: true),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () {
                      if (widget.store
                          .renameCustomCategory(oldName, controller.text)) {
                        Navigator.pop(c, controller.text.trim());
                      }
                    },
                    child: const Text('Save'))
              ],
            ));
    return value;
  }

  Future<String?> createCustomProject() async {
    final controller = TextEditingController();
    String? error;
    final result = await ownedTextDialog<String>(
        context,
        controller,
        (dialogContext) => StatefulBuilder(
            builder: (dialogContext, update) => AlertDialog(
                  title: const Text('Create a project'),
                  content: TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                          labelText: 'Project name',
                          hintText: 'Backend learning path',
                          errorText: error)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () {
                          final value = controller.text.trim();
                          if (value.isEmpty ||
                              widget.store.projects.any((p) =>
                                  p.name.toLowerCase() ==
                                  value.toLowerCase())) {
                            update(() => error = 'Use a unique project name.');
                            return;
                          }
                          final project =
                              Project(id: widget.store.id(), name: value);
                          widget.store.addProject(project);
                          Navigator.pop(dialogContext, project.id);
                        },
                        child: const Text('Create project'))
                  ],
                )));
    return result;
  }

  @override
  Widget build(BuildContext c) {
    final parsed = smart
        ? QuickCapture.parse(title.text, DateTime.now())
        : QuickCapture(title.text);
    final p = widget.store.project(projectId);
    return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
        child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 1,
            child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: 640,
                    maxHeight: MediaQuery.sizeOf(c).height * .92),
                child: Container(
                    decoration: BoxDecoration(
                        color: surface(c),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24))),
                    child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                  child: Container(
                                      width: 35,
                                      height: 4,
                                      decoration: BoxDecoration(
                                          color: hairline(c),
                                          borderRadius:
                                              BorderRadius.circular(9)))),
                              const SizedBox(height: 18),
                              Row(children: [
                                Icon(
                                    widget.parentId != null
                                        ? Icons.subdirectory_arrow_right
                                        : Icons.add_task_rounded,
                                    size: 18,
                                    color: accent),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(
                                        widget.task == null
                                            ? widget.parentId != null
                                                ? 'A smaller step'
                                                : 'Capture a thought'
                                            : 'Edit task',
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600))),
                                IconButton(
                                    tooltip: 'Close editor',
                                    onPressed: () => Navigator.pop(c),
                                    icon: const Icon(Icons.close, size: 20))
                              ]),
                              TextField(
                                  controller: title,
                                  autofocus: widget.task == null,
                                  maxLines: null,
                                  onChanged: (_) => setState(() {}),
                                  style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -.5),
                                  decoration: InputDecoration(
                                      hintText: 'What’s on your mind?',
                                      errorText: error,
                                      filled: false,
                                      border: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              vertical: 16))),
                              TextField(
                                  controller: notes,
                                  maxLines: 2,
                                  minLines: 1,
                                  style: const TextStyle(fontSize: 13),
                                  decoration: const InputDecoration(
                                      hintText:
                                          'Description, notes, or a useful link…',
                                      filled: false,
                                      border: InputBorder.none,
                                      contentPadding:
                                          EdgeInsets.only(bottom: 16))),
                              if (smart &&
                                  (parsed.date != null ||
                                      parsed.hasPriority ||
                                      parsed.labels.isNotEmpty ||
                                      parsed.recurrence.isNotEmpty ||
                                      parsed.projectName != null))
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 17),
                                    child: Wrap(
                                        spacing: 7,
                                        runSpacing: 7,
                                        children: [
                                          const Pill('Recognized',
                                              icon: Icons.auto_awesome_outlined,
                                              color: sage),
                                          if (parsed.date != null)
                                            Pill(
                                                '${dateLabel(parsed.date!)} ${parsed.date!.hour == 0 ? '' : timeLabel(parsed.date!)}',
                                                color: sage),
                                          if (parsed.hasPriority)
                                            Pill('P${parsed.priority}',
                                                color: priorityColor(
                                                    parsed.priority)),
                                          for (final label in parsed.labels)
                                            Pill(label, color: violet),
                                          if (parsed.projectName != null)
                                            Pill('#${parsed.projectName}'),
                                          if (parsed.recurrence.isNotEmpty)
                                            Pill(parsed.recurrence, color: sage)
                                        ])),
                              Wrap(spacing: 8, runSpacing: 9, children: [
                                Pill(
                                    scheduled == null
                                        ? 'Date'
                                        : '${dateLabel(scheduled!)}${scheduled!.hour == 0 ? '' : ' · ${timeLabel(scheduled!)}'}',
                                    icon: Icons.calendar_today_outlined,
                                    color: sage, onTap: () async {
                                  final d = await chooseDate(scheduled);
                                  if (d != null) setState(() => scheduled = d);
                                }),
                                Pill('Priority $priority',
                                    icon: Icons.flag_outlined,
                                    color: priorityColor(priority), onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => priority = priority % 4 + 1);
                                }),
                                Pill(
                                    reminder == null
                                        ? 'Reminder'
                                        : dateLabel(reminder!),
                                    icon: Icons.notifications_none_rounded,
                                    color: violet, onTap: () async {
                                  final d = await chooseDate(reminder);
                                  if (d != null) setState(() => reminder = d);
                                }),
                                Pill(more ? 'Fewer details' : 'More details',
                                    icon: Icons.tune_rounded,
                                    color: secondary(c),
                                    onTap: () => setState(() => more = !more))
                              ]),
                              const SizedBox(height: 16),
                              if (widget.task == null)
                                Text(
                                    'Try “Read chapter 3 tomorrow at 9am p2 @study”.',
                                    style: TextStyle(
                                        color: secondary(c), fontSize: 11)),
                              if (more) ...[
                                const SizedBox(height: 18),
                                const Divider(),
                                const SizedBox(height: 15),
                                Wrap(spacing: 8, children: [
                                  TextButton(
                                      onPressed: () => setState(() =>
                                          scheduled = day(DateTime.now())),
                                      child: const Text('Today')),
                                  TextButton(
                                      onPressed: () => setState(() =>
                                          scheduled = day(DateTime.now())
                                              .add(const Duration(days: 1))),
                                      child: const Text('Tomorrow')),
                                  TextButton(
                                      onPressed: () =>
                                          setState(() => scheduled = null),
                                      child: const Text('No date')),
                                  if (reminder != null)
                                    TextButton(
                                        onPressed: () =>
                                            setState(() => reminder = null),
                                        child: const Text('Remove reminder'))
                                ]),
                                if (reminder != null)
                                  Text(
                                      'In-app reminder: ${dateLabel(reminder!)} at ${timeLabel(reminder!)}. GRIT must be open.',
                                      style: TextStyle(
                                          color: secondary(c), fontSize: 11)),
                                const SizedBox(height: 15),
                                TextField(
                                    controller: labels,
                                    decoration: const InputDecoration(
                                        labelText: 'Labels',
                                        hintText:
                                            'study, deep-work, personal')),
                                const SizedBox(height: 15),
                                Row(children: [
                                  Expanded(
                                      child: GritChoiceField<String>(
                                          key: ValueKey('repeat:$recurrence'),
                                          initialValue:
                                              recurrence.contains('FREQ=')
                                                  ? 'custom'
                                                  : recurrence,
                                          isExpanded: true,
                                          decoration: const InputDecoration(
                                              labelText: 'Repeat'),
                                          items: {
                                            '': 'Does not repeat',
                                            'daily': 'Every day',
                                            'weekdays': 'Every weekday',
                                            'weekly': 'Every week',
                                            'monthly': 'Every month',
                                            'custom': 'Custom RRULE'
                                          }
                                              .entries
                                              .map((e) => DropdownMenuItem(
                                                  value: e.key,
                                                  child: Text(e.value,
                                                      style: const TextStyle(
                                                          fontSize: 12))))
                                              .toList(),
                                          onChanged: (v) => setState(() =>
                                              recurrence = v == 'custom'
                                                  ? customRule.text
                                                  : v!))),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: GritChoiceField<String>(
                                          key: ValueKey(
                                              'category:$categoryValue:$categoryRevision:${widget.store.customCategories.join(',')}'),
                                          initialValue: categoryValue,
                                          isExpanded: true,
                                          decoration: const InputDecoration(
                                              labelText: 'Category'),
                                          items: [
                                            ...Category.values.map((v) =>
                                                DropdownMenuItem(
                                                    value: v.name,
                                                    child: Text(v.label,
                                                        style: const TextStyle(
                                                            fontSize: 12)))),
                                            ...widget.store.customCategories
                                                .map((name) => DropdownMenuItem(
                                                    value: 'custom:$name',
                                                    child: Text(name,
                                                        style: const TextStyle(
                                                            fontSize: 12)))),
                                            const DropdownMenuItem(
                                                value: '__other__',
                                                child: Text('Other…',
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600)))
                                          ],
                                          onChanged: (value) async {
                                            if (value == '__other__') {
                                              final created =
                                                  await manageCustomCategories();
                                              if (mounted) {
                                                setState(
                                                    () => categoryRevision++);
                                              }
                                              if (created != null && mounted) {
                                                setState(() => categoryValue =
                                                    'custom:$created');
                                              } else if (mounted) {
                                                setState(() {
                                                  if (categoryValue.startsWith(
                                                          'custom:') &&
                                                      !widget.store
                                                          .customCategories
                                                          .contains(
                                                              categoryValue
                                                                  .substring(
                                                                      7))) {
                                                    categoryValue = Category
                                                        .personalProject.name;
                                                  }
                                                });
                                              }
                                            } else if (value != null) {
                                              setState(
                                                  () => categoryValue = value);
                                            }
                                          }))
                                ]),
                                const SizedBox(height: 18),
                                if (recurrence.contains('FREQ=')) ...[
                                  TextField(
                                      controller: customRule,
                                      decoration: const InputDecoration(
                                          labelText: 'Recurrence rule',
                                          hintText:
                                              'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR')),
                                  const SizedBox(height: 8),
                                  Text(
                                      'Daily, weekly, monthly or yearly. Supports interval, weekdays, month days, months, count and until. Advanced time and set-position clauses are rejected.',
                                      style: TextStyle(
                                          fontSize: 11, color: secondary(c))),
                                  const SizedBox(height: 16)
                                ],
                                Text('Estimated effort · $minutes min',
                                    style: const TextStyle(fontSize: 12)),
                                Slider(
                                    value: minutes.toDouble().clamp(5, 240),
                                    min: 5,
                                    max: 240,
                                    divisions: 47,
                                    onChanged: (v) =>
                                        setState(() => minutes = v.round())),
                                Wrap(spacing: 8, children: [
                                  OutlinedButton.icon(
                                      onPressed: () async {
                                        final d = await chooseDate(deadline);
                                        if (d != null) {
                                          setState(() => deadline = d);
                                        }
                                      },
                                      icon: const Icon(Icons.flag_outlined,
                                          size: 15),
                                      label: Text(deadline == null
                                          ? 'Set a fixed deadline'
                                          : 'Deadline ${dateLabel(deadline!)}')),
                                  if (deadline != null)
                                    IconButton(
                                        tooltip: 'Remove deadline',
                                        onPressed: () =>
                                            setState(() => deadline = null),
                                        icon: const Icon(Icons.close, size: 17))
                                ]),
                                if (widget.task == null)
                                  SwitchListTile.adaptive(
                                      contentPadding: EdgeInsets.zero,
                                      value: smart,
                                      onChanged: (v) =>
                                          setState(() => smart = v),
                                      title: const Text(
                                          'Recognize dates and labels in task name',
                                          style: TextStyle(fontSize: 12)))
                              ],
                              const Divider(height: 30),
                              Flex(
                                  direction:
                                      MediaQuery.textScalerOf(c).scale(17) > 25
                                          ? Axis.vertical
                                          : Axis.horizontal,
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      MediaQuery.textScalerOf(c).scale(17) > 25
                                          ? CrossAxisAlignment.stretch
                                          : CrossAxisAlignment.center,
                                  children: [
                                    Flexible(
                                        fit: FlexFit.loose,
                                        child: GritChoiceField<String>(
                                            key: ValueKey(
                                                '$projectId:$projectRevision'),
                                            initialValue: projectId ?? 'inbox',
                                            isExpanded: true,
                                            decoration: const InputDecoration(
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 9),
                                                prefixIcon:
                                                    Icon(Icons.tag, size: 16)),
                                            items: [
                                              const DropdownMenuItem(
                                                  value: 'inbox',
                                                  child: Text('Inbox',
                                                      style: TextStyle(
                                                          fontSize: 12))),
                                              ...widget.store.projects
                                                  .where((p) =>
                                                      !p.archived ||
                                                      p.id == projectId)
                                                  .map((p) => DropdownMenuItem(
                                                      value: p.id,
                                                      child: Text(p.name,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                                  fontSize:
                                                                      12)))),
                                              const DropdownMenuItem(
                                                  value: '__other_project__',
                                                  child: Text('Other…',
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w600)))
                                            ],
                                            onChanged: widget.parentId != null
                                                ? null
                                                : (v) async {
                                                    if (v ==
                                                        '__other_project__') {
                                                      final created =
                                                          await createCustomProject();
                                                      if (mounted) {
                                                        setState(() =>
                                                            projectRevision++);
                                                      }
                                                      if (created != null &&
                                                          mounted) {
                                                        setState(() {
                                                          projectId = created;
                                                          section = '';
                                                        });
                                                      }
                                                    } else if (v != null) {
                                                      setState(() {
                                                        projectId = v == 'inbox'
                                                            ? null
                                                            : v;
                                                        section = '';
                                                      });
                                                    }
                                                  })),
                                    const SizedBox(width: 14, height: 14),
                                    FilledButton(
                                        onPressed: save,
                                        child: Text(widget.task == null
                                            ? 'Add task'
                                            : 'Save'))
                                  ]),
                              if (p != null) ...[
                                const SizedBox(height: 12),
                                GritChoiceField<String>(
                                    key: ValueKey('$projectId:$section'),
                                    initialValue: p.sections.contains(section)
                                        ? section
                                        : '',
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                        labelText: 'Section'),
                                    items: [
                                      const DropdownMenuItem(
                                          value: '',
                                          child: Text('Unsectioned',
                                              style: TextStyle(fontSize: 12))),
                                      ...p.sections.map((v) => DropdownMenuItem(
                                          value: v,
                                          child: Text(v,
                                              style: const TextStyle(
                                                  fontSize: 12))))
                                    ],
                                    onChanged: (v) =>
                                        setState(() => section = v!))
                              ]
                            ]))))));
  }

  void save() {
    final q = smart
        ? QuickCapture.parse(title.text, DateTime.now())
        : QuickCapture(title.text);
    if (q.title.trim().isEmpty) {
      setState(() => error = 'Give this task a name.');
      return;
    }
    final store = widget.store;
    final selectedRule =
        recurrence.contains('FREQ=') ? customRule.text.trim() : recurrence;
    try {
      if (selectedRule.isNotEmpty) RecurrenceRule.parse(selectedRule);
    } on FormatException catch (e) {
      setState(() => error = e.message);
      return;
    }
    store.checkpoint();
    String? target = projectId;
    if (q.projectName != null) {
      final found = store.projects
          .where((p) => p.name.toLowerCase() == q.projectName!.toLowerCase())
          .toList();
      if (found.isEmpty) {
        setState(() => error =
            'Project “${q.projectName}” doesn’t exist. Choose a project below.');
        return;
      }
      target = found.first.id;
    }
    final t = widget.task ?? Task(id: store.id(), title: q.title);
    final previousScheduled = t.scheduled;
    t.title = q.title;
    t.notes = notes.text.trim();
    t.labels = {
      ...labels.text.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty),
      ...q.labels
    }.toList();
    t.projectId = target;
    t.section = section;
    t.parentId = widget.parentId ?? t.parentId;
    t.priority = q.hasPriority ? q.priority : priority;
    t.importance = [5, 4, 3, 2][t.priority - 1];
    t.scheduled = q.date ?? scheduled;
    final finalRule = q.recurrence.isNotEmpty ? q.recurrence : selectedRule;
    if (t.recurrence != finalRule || t.scheduled != previousScheduled) {
      t.recurrenceAnchor = t.scheduled ?? day(DateTime.now());
    }
    t.recurrence = finalRule;
    if (categoryValue.startsWith('custom:')) {
      t.category = Category.personalProject;
      t.customCategory = categoryValue.substring('custom:'.length);
    } else {
      t.category = Category.values.firstWhere(
          (value) => value.name == categoryValue,
          orElse: () => Category.personalProject);
      t.customCategory = '';
    }
    t.minutes = minutes;
    t.deadline = deadline;
    t.reminder = reminder;
    if (widget.task == null) store.tasks.add(t);
    for (final child in store.descendants(t.id)) {
      child.projectId = t.projectId;
      child.section = t.section;
    }
    store.record(widget.task == null ? 'Added' : 'Updated', t.title);
    store.save();
    Navigator.pop(context);
  }
}

class FocusSession extends StatefulWidget {
  const FocusSession(
      {super.key,
      required this.task,
      required this.store,
      required this.onComplete});
  final Task task;
  final GritStore store;
  final VoidCallback onComplete;
  @override
  State<FocusSession> createState() => _FocusSessionState();
}

class _FocusSessionState extends State<FocusSession> {
  Timer? timer;
  bool finished = false;
  late final int total;
  Task get task =>
      widget.store.tasks.where((t) => t.id == widget.task.id).firstOrNull ??
      widget.task;
  bool get running => task.focusStartedAt != null;
  int get remaining =>
      finished ? 0 : max(0, total - widget.store.focusElapsed(task) ~/ 1000);
  void finish() {
    widget.store.finishFocus(task);
    finished = true;
  }

  @override
  void initState() {
    super.initState();
    total = min(25, max(1, task.minutes)) * 60;
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && running) {
        if (remaining == 0) finish();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    if (task.focusSessionId != null) {
      final current = task;
      scheduleMicrotask(() => widget.store.finishFocus(current));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AlertDialog(
          scrollable: true,
          content: SizedBox(
              width: 390,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Pill('ONE THING AT A TIME',
                    color: sage, icon: Icons.spa_outlined),
                const SizedBox(height: 24),
                Text(task.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w600)),
                const SizedBox(height: 28),
                SizedBox(
                    width: 205,
                    height: 205,
                    child: Stack(alignment: Alignment.center, children: [
                      SizedBox.expand(
                          child: CircularProgressIndicator(
                              value: remaining / total,
                              color: sage,
                              backgroundColor: sage.withValues(alpha: .1),
                              strokeWidth: 4)),
                      Text(
                          '${(remaining ~/ 60).toString().padLeft(2, '0')}:${(remaining % 60).toString().padLeft(2, '0')}',
                          style: const TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w300,
                              letterSpacing: -2))
                    ])),
                const SizedBox(height: 24),
                Text(
                    finished
                        ? 'Session saved to this task.'
                        : 'Focus time is saved when you pause or close.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: secondary(c), fontSize: 12)),
                const SizedBox(height: 8),
                Text(
                    '${(task.actualSeconds / 60).toStringAsFixed(1)} min logged · ${task.minutes} min estimated',
                    style: TextStyle(color: secondary(c), fontSize: 12)),
                if (!finished) ...[
                  const SizedBox(height: 6),
                  Text(
                      '${(widget.store.focusElapsed(task) / 60000).toStringAsFixed(1)} min this session',
                      style: TextStyle(color: secondary(c), fontSize: 12)),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                    onPressed: () => setState(() {
                          if (running) {
                            widget.store.pauseFocus(task);
                          } else {
                            finished = false;
                            widget.store.startFocus(task);
                          }
                        }),
                    icon:
                        Icon(running ? Icons.pause : Icons.play_arrow_rounded),
                    label: Text(running
                        ? 'Pause'
                        : finished
                            ? 'Start another session'
                            : 'Start focus')),
                TextButton(
                    onPressed: () {
                      finish();
                      widget.onComplete();
                      Navigator.pop(c);
                    },
                    child: const Text('Complete task'))
              ])),
          actions: [
            TextButton(
                onPressed: () {
                  finish();
                  Navigator.pop(c);
                },
                child: const Text('Close session'))
          ]);
}
