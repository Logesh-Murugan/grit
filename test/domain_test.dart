import 'package:flutter_test/flutter_test.dart';
import 'package:grit/domain.dart';

void main() {
  final now = DateTime(2026, 9, 30, 12);
  const engine = PriorityEngine();
  Task task(String id,
          {int minutes = 30,
          int importance = 3,
          DateTime? deadline,
          Category category = Category.assignment}) =>
      Task(
          id: id,
          title: id,
          minutes: minutes,
          importance: importance,
          deadline: deadline,
          category: category);
  test('urgency increases near deadline and remains bounded overdue', () {
    final t = task('a', deadline: now.add(const Duration(days: 4)));
    final distant = engine.urgency(t, now);
    t.deadline = now.add(const Duration(hours: 2));
    expect(engine.urgency(t, now), greaterThan(distant));
    t.deadline = now.subtract(const Duration(days: 4));
    expect(engine.urgency(t, now), 1);
  });
  test('agenda fits capacity while skipping oversized tasks', () {
    final a = task('a', minutes: 120, importance: 5),
        b = task('b', minutes: 25),
        c = task('c', minutes: 30);
    expect(engine.agenda([a, b, c], now, 60), [b, c]);
  });
  test('overdue stays visible even snoozed and over capacity', () {
    final a =
        task('a', minutes: 90, deadline: now.subtract(const Duration(hours: 2)))
          ..snoozedUntil = now.add(const Duration(days: 1));
    expect(engine.agenda([a], now, 30), [a]);
  });
  test('manual pin includes task beyond capacity', () {
    final a = task('a', minutes: 90)..pinnedDay = dayKey(now);
    expect(engine.agenda([a], now, 30), [a]);
    expect(engine.agenda([a], now.add(const Duration(days: 1)), 30), isEmpty);
  });
  test('completed tasks are excluded and habits return tomorrow', () {
    final a = task('a')..doneAt = now;
    final b = task('b', category: Category.habit)..history = [dayKey(now)];
    expect(engine.agenda([a, b], now, 120), isEmpty);
    expect(engine.agenda([a, b], now.add(const Duration(days: 1)), 120), [b]);
  });
  test('a fixed deadline applies to personal work too', () {
    final a = task('a',
        category: Category.personalProject,
        deadline: now.subtract(const Duration(days: 1)));
    expect(a.overdue(now), true);
  });
  test('freeze protects gap without awarding completion', () {
    final t = task('habit', category: Category.habit)
      ..history = [dayKey(now), dayKey(now.subtract(const Duration(days: 2)))];
    expect(streak(t, now), 1);
    expect(
        streak(t, now,
            freezes: {dayKey(now.subtract(const Duration(days: 1)))}),
        2);
  });
  test('task serialization retains scheduling data', () {
    final t = task('a', deadline: now)
      ..pinnedDay = dayKey(now)
      ..history = ['2026-09-29'];
    expect(Task.fromJson(t.toJson()).toJson(), t.toJson());
  });
}
