import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grit/domain.dart';
import 'package:grit/store.dart';
import 'package:grit/task_field_editor.dart';
import 'package:grit/workspace.dart';
import 'package:grit/main.dart';
import 'package:grit/showcase.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('malformed focus and duplicate fields cannot corrupt a backup',
      () async {
    final s = GritStore();
    await s.init(enableCloud: false);
    s.tasks.add(Task(id: 'a', title: 'Keep me'));
    final backup = s.toJson();
    (backup['tasks'] as List).first['focusLogs'] = [
      {'id': 'bad', 'seconds': -1, 'endedAt': '2026-10-01'}
    ];
    expect(() => s.importBackup(jsonEncode(backup)), throwsFormatException);
    expect(s.tasks.single.title, 'Keep me');
    final duplicate = s.toJson();
    (duplicate['tasks'] as List).first['fields'] = [
      TaskField('Course', 'Text', 'A').toJson(),
      TaskField('course', 'Text', 'B').toJson()
    ];
    expect(() => s.importBackup(jsonEncode(duplicate)), throwsFormatException);
    expect(s.tasks.single.fields, isEmpty);
  });
  testWidgets('all card densities and long fields fit a phone Board',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = GritStore();
    await s.init(enableCloud: false);
    loadShowcase(s);
    for (final t in s.tasks) {
      t.fields = [TaskField('Course', 'Text', 'Backend ${'long value ' * 35}')];
    }
    await tester.pumpWidget(GritApp(store: s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Board').first);
    await tester.pumpAndSettle();
    for (final density in ['Compact', 'Comfortable', 'Spacious']) {
      s.density = density;
      s.save();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: density);
    }
    await tester.pumpWidget(const SizedBox());
  });
  test('typed fields validate dates, numbers and survive backup/reload',
      () async {
    final s = GritStore();
    await s.init(enableCloud: false);
    s.tasks.add(Task(id: 'a', title: 'Learn backend', fields: [
      TaskField('Course', 'Text', 'Backend'),
      TaskField('Hours', 'Number', 12.5),
      TaskField('Paid', 'Checkbox', true),
      TaskField('Exam', 'Date', '2026-10-31')
    ]));
    s.save();
    final reloaded = GritStore();
    await reloaded.init(enableCloud: false);
    expect(reloaded.tasks.single.fields.map((f) => f.value),
        ['Backend', 12.5, true, '2026-10-31']);
    expect(
        () => TaskField('Exam', 'Date', '2026-02-30'), throwsFormatException);
    expect(() => TaskField('Hours', 'Number', double.infinity),
        throwsFormatException);
    expect(() => TaskField('Paid', 'Checkbox', 'true'), throwsFormatException);
    final backup = jsonEncode(s.toJson());
    reloaded.importBackup(backup);
    expect(reloaded.tasks.single.fields.last.display, '2026-10-31');
  });
  test('gamification is opt in and density preferences persist', () async {
    final s = GritStore();
    await s.init(enableCloud: false);
    expect(s.gamification, false);
    expect(s.density, 'Comfortable');
    s.gamification = true;
    s.density = 'Compact';
    s.save();
    final next = GritStore();
    await next.init(enableCloud: false);
    expect(next.gamification, true);
    expect(next.taskPadding, 9);
    next.gamification = false;
    next.density = 'Spacious';
    next.save();
    final last = GritStore();
    await last.init(enableCloud: false);
    expect(last.gamification, false);
    expect(last.taskPadding, 23);
  });
  test('focus pause/resume excludes paused time and logs only once', () async {
    final s = GritStore();
    await s.init(enableCloud: false);
    final t = Task(id: 'a', title: 'Study');
    s.tasks.add(t);
    final start = DateTime(2026, 10, 1, 9);
    s.startFocus(t, at: start);
    s.pauseFocus(t, at: start.add(const Duration(minutes: 2)));
    s.startFocus(t, at: start.add(const Duration(minutes: 10)));
    s.finishFocus(t, at: start.add(const Duration(minutes: 13)));
    expect(t.actualSeconds, 300);
    expect(t.focusLogs.length, 1);
    s.finishFocus(t, at: start.add(const Duration(minutes: 20)));
    expect(t.actualSeconds, 300);
    expect(t.focusLogs.length, 1);
    s.duplicate(t);
    expect(s.tasks.last.actualSeconds, 0);
    expect(s.tasks.last.focusSessionId, isNull);
  });
  test('running focus survives reload and caps unattended sessions', () async {
    final s = GritStore();
    await s.init(enableCloud: false);
    final t = Task(id: 'a', title: 'Study', minutes: 10);
    s.tasks.add(t);
    final start = DateTime(2026, 10, 1, 9);
    s.startFocus(t, at: start);
    final next = GritStore();
    await next.init(enableCloud: false);
    next.finishFocus(next.tasks.single,
        at: start.add(const Duration(hours: 2)));
    expect(next.tasks.single.actualSeconds, 600);
  });
  test('only one task runs a timer at a time', () async {
    final s = GritStore();
    await s.init(enableCloud: false);
    final a = Task(id: 'a', title: 'A'), b = Task(id: 'b', title: 'B');
    s.tasks.addAll([a, b]);
    final start = DateTime(2026, 10, 1, 9);
    s.startFocus(a, at: start);
    s.startFocus(b, at: start.add(const Duration(minutes: 1)));
    expect(a.focusStartedAt, isNull);
    expect(a.focusMilliseconds, 60000);
    expect(b.focusStartedAt, isNotNull);
  });
  testWidgets('field editor rejects duplicate names and saves a typed value',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (c) => TextButton(
                    onPressed: () => showDialog<TaskField>(
                        context: c,
                        builder: (_) => TaskFieldEditor(names: ['Course'])),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'course');
    await tester.tap(find.text('Save field'));
    await tester.pumpAndSettle();
    expect(find.textContaining('already'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Client');
    await tester.enterText(find.byType(TextField).last, 'Acme');
    await tester.tap(find.text('Save field'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskFieldEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('closing focus records actual time without completing task',
      (tester) async {
    final s = GritStore();
    await s.init(enableCloud: false);
    final task = Task(id: 'a', title: 'Study');
    s.tasks.add(task);
    s.startFocus(task, at: DateTime.now().subtract(const Duration(seconds: 5)));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (c) => TextButton(
                    onPressed: () => showDialog(
                        context: c,
                        builder: (_) => FocusSession(
                            task: task,
                            store: s,
                            onComplete: () => s.toggle(task))),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close session'));
    await tester.pumpAndSettle();
    expect(task.actualSeconds, greaterThanOrEqualTo(5));
    expect(task.focusLogs.length, 1);
    expect(task.doneAt, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
