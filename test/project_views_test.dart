import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grit/domain.dart';
import 'package:grit/planning.dart';
import 'package:grit/store.dart';
import 'package:grit/main.dart';

Future<void> drop(WidgetTester tester, Finder source, Finder target) async {
  await tester.ensureVisible(source);
  await tester.pumpAndSettle();
  final gesture = await tester.startGesture(tester.getCenter(source));
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(tester.getCenter(target));
  await tester.pump(const Duration(milliseconds: 100));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  test('explicit p4, quoted project and invalid time preserve intent', () {
    final q = QuickCapture.parse(
        'Call tomorrow 12am p4 #"Client work" @urgent', DateTime(2026, 10, 3));
    expect(q.title, 'Call');
    expect(q.date, DateTime(2026, 10, 4));
    expect(q.hasPriority, isTrue);
    expect(q.priority, 4);
    expect(q.projectName, 'Client work');
    expect(q.labels, ['urgent']);
    expect(QuickCapture.parse('Call at 25:99', DateTime(2026)).title,
        'Call at 25:99');
    expect(QuickCapture.parse('Call', DateTime(2026)).hasPriority, isFalse);
  });

  testWidgets(
      'project board and calendar drag same task and persist view and metadata',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = GritStore();
    await store.init(enableCloud: false);
    store.onboarded = true;
    store.projects = [Project(id: 'work', name: 'Work', favorite: true)];
    store.tasks = [
      Task(
          id: 'report',
          title: 'Submit report',
          projectId: 'work',
          section: 'To do',
          labels: ['urgent'],
          priority: 1)
    ];
    await tester.pumpWidget(GritApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Board').first);
    await tester.pumpAndSettle();
    await drop(tester, find.byKey(const ValueKey('board-task-report')),
        find.byKey(const ValueKey('board-column-In progress')));
    expect(store.tasks.single.section, 'In progress');
    await drop(tester, find.byKey(const ValueKey('board-task-report')),
        find.byKey(const ValueKey('project-view-Calendar')));
    expect(store.projects.single.view, 'Calendar');
    final now = DateTime.now();
    final date = DateTime(now.year, now.month, 15);
    await drop(tester, find.byKey(const ValueKey('calendar-task-report')),
        find.byKey(ValueKey('calendar-day-${dayKey(date)}')));
    expect(store.tasks.single.scheduled, date);
    expect(store.tasks.single.section, 'In progress');
    store.tasks.single.scheduled = DateTime(now.year, now.month, 15, 17, 30);
    await store.save();
    await tester.pumpAndSettle();
    final next = DateTime(now.year, now.month, 16);
    await drop(tester, find.byKey(const ValueKey('calendar-task-report')),
        find.byKey(ValueKey('calendar-day-${dayKey(next)}')));
    expect(store.tasks.single.scheduled,
        DateTime(now.year, now.month, 16, 17, 30));
    await drop(tester, find.byKey(const ValueKey('calendar-task-report')),
        find.byKey(const ValueKey('calendar-unscheduled')));
    expect(store.tasks.single.scheduled, isNull);
    expect(store.tasks.single.projectId, 'work');
    expect(store.tasks.single.labels, ['urgent']);
    await store.save();
    final restored = GritStore();
    await restored.init(enableCloud: false);
    expect(restored.projects.single.view, 'Calendar');
    expect(restored.tasks.single.section, 'In progress');
    expect(restored.tasks.single.scheduled, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'requested quick add saves date time project label and priority together',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = GritStore();
    await store.init(enableCloud: false);
    store.onboarded = true;
    store.projects = [Project(id: 'work', name: 'Work')];
    await tester.pumpWidget(GritApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    await tester.enterText(find.byType(TextField).first,
        'Submit report tomorrow 5pm p1 #Work @urgent');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Add task'));
    await tester.tap(find.widgetWithText(FilledButton, 'Add task'));
    await tester.pumpAndSettle();
    final t = store.tasks.single;
    expect(t.title, 'Submit report');
    expect(t.scheduled, DateTime(now.year, now.month, now.day + 1, 17));
    expect(t.priority, 1);
    expect(t.projectId, 'work');
    expect(t.labels, ['urgent']);
    await store.save();
    final restored = GritStore();
    await restored.init(enableCloud: false);
    expect(restored.tasks.single.toJson(), t.toJson());
    await tester.pumpWidget(const SizedBox());
  });
}
