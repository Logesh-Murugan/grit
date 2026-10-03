import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grit/domain.dart';
import 'package:grit/planning.dart';
import 'package:grit/store.dart';

void main() {
  final now = DateTime(2026, 9, 30, 12);
  test('quick capture extracts tomorrow time priority label and project', () {
    final p = QuickCapture.parse(
        'Read chapter 3 tomorrow at 9am p2 @study #University', now);
    expect(p.title, 'Read chapter 3');
    expect(p.date, DateTime(2026, 10, 1, 9));
    expect(p.priority, 2);
    expect(p.labels, ['study']);
    expect(p.projectName, 'University');
  });
  test('quick capture handles noon and midnight', () {
    expect(QuickCapture.parse('Call today at 12pm', now).date!.hour, 12);
    expect(QuickCapture.parse('Read tomorrow at 12am', now).date!.hour, 0);
  });
  test('invalid time remains visible instead of silently changing meaning', () {
    expect(QuickCapture.parse('Study at 25:99', now).title, 'Study at 25:99');
  });
  test('weekly recurrence and labels survive capture', () {
    final p = QuickCapture.parse('Weekly review every week @planning', now);
    expect(p.recurrence, 'weekly');
    expect(p.title, 'Weekly review');
  });
  test(
      'filter parentheses and precedence produce expected cross-project results',
      () {
    final t = Task(
        id: '1',
        title: 'Research',
        priority: 2,
        scheduled: now,
        labels: ['deep-work']);
    expect(
        TaskQuery.matches(t, '(today | overdue) & (p1 | p2) & @deep-work', now),
        true);
    expect(TaskQuery.matches(t, 'today & !@deep-work', now), false);
    expect(
        TaskQuery.matches(t, '#University & no deadline', now,
            projectName: 'University'),
        true);
  });
  test('invalid filter fails even behind a matching OR condition', () {
    final t = Task(id: '1', title: 'x', scheduled: now);
    expect(() => TaskQuery.matches(t, 'today | unsupported', now),
        throwsFormatException);
    expect(() => TaskQuery.matches(t, '(today', now), throwsFormatException);
    expect(() => TaskQuery.matches(t, 'today &', now), throwsFormatException);
  });
  test('monthly recurrence handles short months', () {
    expect(
        nextOccurrence(
            DateTime(2026, 1, 31, 9), 'monthly', DateTime(2026, 1, 31)),
        DateTime(2026, 2, 28, 9));
  });
  test('weekday recurrence skips weekends', () {
    expect(
        nextOccurrence(
            DateTime(2026, 10, 2, 9), 'weekdays', DateTime(2026, 10, 2)),
        DateTime(2026, 10, 5, 9));
  });
  test('completing a late recurring task advances past missed dates', () {
    expect(nextOccurrence(DateTime(2026, 9, 20, 9), 'daily', now),
        DateTime(2026, 9, 30, 9));
  });
  test('project metadata and comments survive persistence', () async {
    SharedPreferences.setMockInitialValues({});
    final s = GritStore();
    await s.init();
    s.addProject(Project(id: 'p', name: 'University', favorite: true));
    final t = Task(
        id: '1',
        title: 'Essay',
        projectId: 'p',
        section: 'To do',
        priority: 2,
        labels: ['study']);
    s.addTask(t);
    s.addComment(t, 'Outline first');
    await s.save();
    final restored = GritStore();
    await restored.init();
    expect(restored.projects.single.favorite, true);
    expect(restored.tasks.single.comments.single['text'], 'Outline first');
    expect(restored.tasks.single.labels, ['study']);
  });
  test('delete and undo preserve subtasks and user data', () async {
    SharedPreferences.setMockInitialValues({});
    final s = GritStore();
    await s.init();
    final t = Task(id: 'p', title: 'Parent');
    s.tasks = [t, Task(id: 'c', title: 'Child', parentId: 'p')];
    s.deleteTask(t);
    expect(s.activeTasks, isEmpty);
    expect(s.undo(), true);
    expect(s.activeTasks.length, 2);
  });
  test('duplicate creates unique IDs and resets completion', () async {
    SharedPreferences.setMockInitialValues({});
    final s = GritStore();
    await s.init();
    final t = Task(id: 'p', title: 'Parent', doneAt: now);
    s.tasks = [t, Task(id: 'c', title: 'Child', parentId: 'p', doneAt: now)];
    s.duplicate(t);
    expect(s.tasks.length, 4);
    expect(s.tasks.map((t) => t.id).toSet().length, 4);
    expect(s.tasks.last.doneAt, isNull);
    expect(s.tasks.last.parentId, s.tasks[2].id);
  });
  test('invalid backup is rejected atomically', () async {
    SharedPreferences.setMockInitialValues({});
    final s = GritStore();
    await s.init();
    s.tasks = [Task(id: 'keep', title: 'Keep me')];
    expect(
        () => s.importBackup(jsonEncode({
              'tasks': [],
              'projects': [
                {'broken': true}
              ]
            })),
        throwsA(anything));
    expect(s.tasks.single.id, 'keep');
    expect(() => s.importBackup(jsonEncode({'tasks': [], 'capacity': 0})),
        throwsFormatException);
    expect(s.tasks.single.id, 'keep');
  });
  test('recurring completion earns credit and is undoable', () async {
    SharedPreferences.setMockInitialValues({});
    final s = GritStore();
    await s.init();
    final t = Task(
        id: 'r',
        title: 'Read',
        recurrence: 'daily',
        scheduled: day(DateTime.now()),
        minutes: 20);
    s.tasks = [t];
    s.toggle(t);
    expect(s.completedOn(DateTime.now()), 1);
    expect(s.completedMinutesToday, 20);
    expect(t.doneAt, isNull);
    expect(s.undo(), true);
    expect(s.completedOn(DateTime.now()), 0);
  });
  test('nested tasks move, duplicate and trash as one tree', () async {
    SharedPreferences.setMockInitialValues({});
    final s = GritStore();
    await s.init();
    final root = Task(id: 'root', title: 'Root');
    s.tasks = [
      root,
      Task(id: 'child', title: 'Child', parentId: 'root'),
      Task(id: 'leaf', title: 'Leaf', parentId: 'child')
    ];
    s.move(root, 'project', 'Next');
    expect(
        s.tasks.every((t) => t.projectId == 'project' && t.section == 'Next'),
        true);
    s.duplicate(root);
    final copy = s.tasks.firstWhere((t) => t.title == 'Root (copy)');
    expect(s.descendants(copy.id).length, 2);
    expect(s.tasks.map((t) => t.id).toSet().length, 6);
    s.deleteTask(root);
    expect(s.tasks.where((t) => t.trashed).length, 3);
    s.restoreTask(root);
    expect(s.tasks.any((t) => t.trashed), false);
  });
  test('bulk completion undoes the entire selection', () async {
    SharedPreferences.setMockInitialValues({});
    final s = GritStore();
    await s.init();
    s.tasks = [Task(id: 'a', title: 'A'), Task(id: 'b', title: 'B')];
    s.completeMany({'a', 'b'});
    expect(s.completedOn(DateTime.now()), 2);
    s.undo();
    expect(s.completedOn(DateTime.now()), 0);
  });
}
