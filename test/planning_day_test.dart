import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grit/domain.dart';
import 'package:grit/planning.dart';
import 'package:grit/main.dart';
import 'package:grit/store.dart';
import 'package:grit/workspace.dart';

void main() {
  test('planning dates isolate tasks, blocks, snooze and daily completion', () {
    final today = DateTime(2026, 12, 31);
    final tomorrow = DateTime(2027, 1, 1);
    final tasks = [
      Task(id: 'today', title: 'Today', scheduled: today),
      Task(id: 'tomorrow', title: 'Tomorrow', scheduled: tomorrow),
      Task(id: 'old', title: 'Old', scheduled: DateTime(2026, 12, 30)),
      Task(
          id: 'block',
          title: 'Block',
          scheduled: tomorrow,
          blockStart: DateTime(2027, 1, 1, 9)),
      Task(
          id: 'habit',
          title: 'Habit',
          category: Category.habit,
          recurrence: 'daily',
          scheduled: today,
          blockStart: DateTime(2026, 12, 31, 8),
          history: [dayKey(today)]),
      Task(
          id: 'snooze',
          title: 'Snoozed',
          scheduled: tomorrow,
          snoozedUntil: DateTime(2027, 1, 2)),
    ];
    expect(
        planningDayTasks(tasks, today, now: today, carryOver: true)
            .map((t) => t.id),
        ['today', 'old']);
    expect(
        planningDayTasks(tasks, tomorrow, now: today, carryOver: true)
            .map((t) => t.id),
        ['tomorrow', 'block', 'habit']);
  });
  testWidgets('Schedule and Calendar use selected day beyond Today filter',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = GritStore();
    await store.init(enableCloud: false);
    store.onboarded = true;
    final today = day(DateTime.now());
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    store.tasks = [
      Task(id: 'today', title: 'Only today', scheduled: today),
      Task(id: 'tomorrow', title: 'Only tomorrow', scheduled: tomorrow),
      Task(
          id: 'child',
          title: 'Nested tomorrow',
          scheduled: tomorrow,
          parentId: 'tomorrow'),
      Task(
          id: 'future-block',
          title: 'Tomorrow block',
          scheduled: tomorrow,
          blockStart: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9)),
    ];
    await tester.pumpWidget(GritApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schedule').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('schedule-task-today')), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-task-tomorrow')), findsNothing);
    await tester.tap(find.byTooltip('Next day'));
    await tester.pumpAndSettle();
    expect(find.text('Tomorrow'), findsWidgets);
    expect(find.byKey(const ValueKey('schedule-task-child')), findsNothing);
    expect(find.byKey(const ValueKey('schedule-task-today')), findsNothing);
    expect(
        find.byKey(const ValueKey('schedule-task-tomorrow')), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-block-future-block')),
        findsOneWidget);
    await tester.tap(find.text('Calendar').first);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('calendar-task-tomorrow')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-task-future-block')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-task-today')), findsNothing);
    await tester.ensureVisible(find.text('Add to this day'));
    await tester.tap(find.text('Add to this day'));
    await tester.pumpAndSettle();
    expect(tester.widget<TaskEditor>(find.byType(TaskEditor)).date, tomorrow);
    await tester.tap(find.byTooltip('Close editor'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Schedule').first);
    await tester.tap(find.text('Schedule').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous day'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('schedule-task-today')), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-task-tomorrow')), findsNothing);
    await tester.tap(find.byTooltip('Next day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go to today').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('schedule-task-today')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
