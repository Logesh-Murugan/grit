import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grit/domain.dart';
import 'package:grit/store.dart';
import 'package:grit/planning.dart';
import 'package:grit/recurrence.dart';
import 'package:grit/calendar_export.dart';
import 'package:grit/record_sync.dart';
import 'package:grit/main.dart';

void main() {
  test('requested quick capture parses bare 5pm and all metadata', () {
    final q = QuickCapture.parse(
        'Submit report tomorrow 5pm p1 #Work @urgent', DateTime(2026, 10, 1));
    expect(q.title, 'Submit report');
    expect(q.date, DateTime(2026, 10, 2, 17));
    expect(q.priority, 1);
    expect(q.projectName, 'Work');
    expect(q.labels, ['urgent']);
  });
  test('biweekly weekdays use anchor week and retain time', () {
    final anchor = DateTime(2026, 10, 5, 9);
    final r = RecurrenceRule.parse('FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR');
    expect(r.next(anchor, anchor), DateTime(2026, 10, 9, 9));
    expect(r.next(anchor, DateTime(2026, 10, 9, 9)), DateTime(2026, 10, 19, 9));
  });
  test('ordinal month weekday, negative month day and yearly leap day', () {
    final a = DateTime(2026, 10, 1, 8);
    expect(RecurrenceRule.parse('FREQ=MONTHLY;BYDAY=1MO').next(a, a),
        DateTime(2026, 10, 5, 8));
    expect(RecurrenceRule.parse('FREQ=MONTHLY;BYMONTHDAY=-1').next(a, a),
        DateTime(2026, 10, 31, 8));
    final leap = DateTime(2024, 2, 29);
    expect(RecurrenceRule.parse('FREQ=YEARLY').next(leap, leap),
        DateTime(2028, 2, 29));
  });
  test('COUNT and UNTIL stop recurrence; unsupported rules fail', () {
    final a = DateTime(2026, 10, 1);
    expect(RecurrenceRule.parse('FREQ=DAILY;COUNT=2').next(a, a),
        DateTime(2026, 10, 2));
    expect(
        RecurrenceRule.parse('FREQ=DAILY;COUNT=2')
            .next(a, DateTime(2026, 10, 2)),
        isNull);
    expect(
        RecurrenceRule.parse('FREQ=DAILY;UNTIL=20261001').next(a, a), isNull);
    for (final rule in [
      'FREQ=HOURLY',
      'FREQ=WEEKLY;BYDAY=1MO',
      'FREQ=DAILY;BYHOUR=9',
      'FREQ=DAILY;COUNT=2;UNTIL=20261101',
      'FREQ=DAILY;UNTIL=20260230'
    ]) {
      expect(() => RecurrenceRule.parse(rule), throwsFormatException,
          reason: rule);
    }
  });
  test('monthly task restores original day after February', () {
    final t = Task(
        id: 'm',
        title: 'Monthly',
        scheduled: DateTime(2026, 1, 31),
        recurrence: 'monthly');
    t.scheduled = nextTaskOccurrence(t, DateTime(2026, 1, 31));
    expect(t.scheduled, DateTime(2026, 2, 28));
    t.scheduled = nextTaskOccurrence(t, DateTime(2026, 2, 28));
    expect(t.scheduled, DateTime(2026, 3, 31));
  });
  test('hierarchy rejects cycles and drag moves only selected project',
      () async {
    SharedPreferences.setMockInitialValues({});
    final s = GritStore();
    await s.init();
    final a = Project(id: 'a', name: 'A'),
        b = Project(id: 'b', name: 'B', parentId: 'a'),
        c = Project(id: 'c', name: 'C', order: 1);
    s.projects = [a, b, c];
    expect(s.projectTree().map((p) => p.id), ['a', 'b', 'c']);
    expect(() => s.reparentProject(a, 'b'), throwsFormatException);
    s.reorderProject(c, a);
    expect(s.projectTree().map((p) => p.id), ['c', 'a', 'b']);
    expect(b.parentId, 'a');
    final raw = s.toJson();
    (raw['projects'] as List)[0]['parentId'] = 'b';
    expect(() => s.importBackup(jsonEncode(raw)), throwsFormatException);
    expect(a.parentId, isNull);
  });
  test('time block rejects overlaps, accepts touching boundaries and undoes',
      () async {
    SharedPreferences.setMockInitialValues({});
    final s = GritStore();
    await s.init();
    final a = Task(id: 'a', title: 'A', minutes: 60),
        b = Task(id: 'b', title: 'B', minutes: 30);
    s.tasks = [a, b];
    s.timeBlock(a, DateTime(2026, 10, 2, 9));
    expect(() => s.timeBlock(b, DateTime(2026, 10, 2, 9, 30)),
        throwsFormatException);
    s.timeBlock(b, DateTime(2026, 10, 2, 10));
    expect(b.blockStart, DateTime(2026, 10, 2, 10));
    s.undo();
    expect(s.tasks.last.blockStart, isNull);
  });
  test('calendar export escapes content, writes UTC duration and folds UTF8',
      () {
    final t = Task(
        id: 'a',
        title: 'Study, code;\n${List.filled(50, '学').join()}',
        notes: 'Path\\file',
        minutes: 45,
        blockStart: DateTime.utc(2026, 10, 2, 9));
    final ics = calendarExport([t], generated: DateTime.utc(2026, 10, 1));
    expect(ics, contains('DTSTART:20261002T090000Z'));
    expect(ics, contains('DTEND:20261002T094500Z'));
    expect(ics, contains('SUMMARY:Study\\, code\\;\\n'));
    expect(ics, contains('Path\\\\file'));
    expect(ics.split('\r\n').every((l) => utf8.encode(l).length <= 75), true);
  });
  test('record sync keeps file bytes device-local and splits entities', () {
    final s = GritStore();
    s.tasks = [
      Task(id: 'a/b', title: 'Task', attachments: [
        {'name': 'file', 'data': 'abc'}
      ])
    ];
    final records = workspaceRecords(s.toJson());
    expect(records, contains('tasks-a%2Fb'));
    expect(records['tasks-a%2Fb']!['data']['attachments'], isEmpty);
    expect(s.tasks.single.attachments, isNotEmpty);
  });
  test('custom categories and project views survive save, rename and reload',
      () async {
    SharedPreferences.setMockInitialValues({});
    final s = GritStore();
    await s.init();
    s.addCustomCategory('Certification');
    s.tasks = [Task(id: 'c', title: 'AWS', customCategory: 'Certification')];
    s.projects = [Project(id: 'p', name: 'Cloud', view: 'Board')];
    s.filters = [SavedFilter('f', 'Urgent', 'p1', favorite: true)];
    s.weeklyGoal = 40;
    s.renameCustomCategory('Certification', 'Cloud certification');
    await s.save();
    final restored = GritStore();
    await restored.init();
    expect(restored.tasks.single.categoryLabel, 'Cloud certification');
    expect(restored.projects.single.view, 'Board');
    expect(restored.filters.single.favorite, true);
    expect(restored.weeklyGoal, 40);
  });
  testWidgets(
      'Other creates category and project from task editor then persists',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final s = GritStore();
    await s.init();
    s.onboarded = true;
    await tester.pumpWidget(GritApp(store: s));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Learn backend');
    await tester.tap(find.text('More details'));
    await tester.pumpAndSettle();
    final category = find.byKey(const ValueKey('category:personalProject:0:'));
    await tester.ensureVisible(category);
    await tester.tap(category);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other…').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'Certification');
    await tester.tap(find.text('Add category'));
    await tester.pumpAndSettle();
    final project = find.byKey(const ValueKey('null:0'));
    await tester.ensureVisible(project);
    await tester.tap(project);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other…').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'Backend path');
    await tester.tap(find.text('Create project'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add task').last);
    await tester.tap(find.text('Add task').last);
    await tester.pumpAndSettle();
    expect(s.tasks.single.customCategory, 'Certification');
    expect(s.projectName(s.tasks.single), 'Backend path');
    expect(tester.takeException(), isNull);
    final restored = GritStore();
    await restored.init();
    expect(restored.projectName(restored.tasks.single), 'Backend path');
    await tester.pumpWidget(const SizedBox());
  });
}
