import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grit/domain.dart';
import 'package:grit/main.dart';
import 'package:grit/store.dart';

Future<void> dragTo(WidgetTester tester, Finder source, Finder target,
    {PointerDeviceKind kind = PointerDeviceKind.mouse}) async {
  await tester.ensureVisible(source);
  await tester.pumpAndSettle();
  final gesture =
      await tester.startGesture(tester.getCenter(source), kind: kind);
  if (kind == PointerDeviceKind.touch) {
    await tester.pump(const Duration(milliseconds: 350));
  }
  await gesture.moveBy(const Offset(8, 8));
  await tester.pump(const Duration(milliseconds: 16));
  await gesture.moveTo(tester.getCenter(target));
  await tester.pump(const Duration(milliseconds: 16));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'Schedule supports immediate mouse and held touch drops, moving, overlap and Undo',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = GritStore();
    await store.init(enableCloud: false);
    store.onboarded = true;
    final today = day(DateTime.now());
    final report = Task(
        id: 'report',
        title: 'Finish the research proposal',
        scheduled: today,
        minutes: 60);
    final read = Task(
        id: 'read', title: 'Read ten pages', scheduled: today, minutes: 30);
    store.tasks = [report, read];
    await tester.pumpWidget(GritApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schedule').first);
    await tester.pumpAndSettle();
    await dragTo(tester, find.byKey(const ValueKey('schedule-task-report')),
        find.byKey(const ValueKey('schedule-hour-1')));
    expect(report.blockStart, today.add(const Duration(hours: 1)));
    expect(report.scheduled, report.blockStart);
    // The visible block itself can be dragged to another hour.
    await dragTo(tester, find.byKey(const ValueKey('schedule-block-report')),
        find.byKey(const ValueKey('schedule-hour-2')));
    expect(report.blockStart, today.add(const Duration(hours: 2)));
    await tester.tap(find.text('Undo').last);
    await tester.pumpAndSettle();
    // Undo restores objects from the snapshot, so inspect the current store.
    expect(store.tasks.first.blockStart, today.add(const Duration(hours: 1)));
    await dragTo(tester, find.byKey(const ValueKey('schedule-task-read')),
        find.byKey(const ValueKey('schedule-hour-3')),
        kind: PointerDeviceKind.touch);
    expect(store.tasks.last.blockStart, today.add(const Duration(hours: 3)));
    await dragTo(tester, find.byKey(const ValueKey('schedule-block-report')),
        find.byKey(const ValueKey('schedule-hour-3')));
    expect(store.tasks.first.blockStart, today.add(const Duration(hours: 1)));
    expect(
        find.text('This block overlaps another task. Choose a different time.'),
        findsOneWidget);
    await store.save();
    final restored = GritStore();
    await restored.init(enableCloud: false);
    expect(restored.tasks.last.blockStart, today.add(const Duration(hours: 3)));
    await dragTo(tester, find.byKey(const ValueKey('schedule-block-report')),
        find.byKey(const ValueKey('schedule-hour-4')));
    store.tasks.first.title = 'Keep my newer edit';
    await store.save();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo').last);
    await tester.pumpAndSettle();
    expect(store.tasks.first.title, 'Keep my newer edit');
    expect(store.tasks.first.blockStart, today.add(const Duration(hours: 4)));
    expect(find.text('A newer edit was made. Open the task to change it.'),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test('stale Undo preserves newer changes; scheduling clears snooze',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = GritStore();
    await store.init(enableCloud: false);
    final task = Task(id: 'guard', title: 'Original');
    store.tasks = [task];
    store.snooze(task);
    store.timeBlock(task, day(DateTime.now()).add(const Duration(hours: 9)));
    expect(task.snoozedUntil, isNull);
    final revision = store.undoRevision;
    task.title = 'Newer edit';
    await store.save();
    expect(store.undo(expectedRevision: revision), isFalse);
    expect(store.tasks.single.title, 'Newer edit');
    expect(store.tasks.single.blockStart, isNotNull);
    store.schedule(task, null);
    expect(store.undo(expectedRevision: store.undoRevision), isTrue);
    expect(store.tasks.single.title, 'Newer edit');
    expect(store.tasks.single.blockStart, isNotNull);
  });
  testWidgets('Schedule drag scrolls near viewport edge to reach later hours',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = GritStore();
    await store.init(enableCloud: false);
    store.onboarded = true;
    store.tasks = [
      Task(
          id: 'scroll',
          title: 'Reach a later hour',
          scheduled: day(DateTime.now()))
    ];
    await tester.pumpWidget(GritApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schedule').first);
    await tester.pumpAndSettle();
    final source = find.byKey(const ValueKey('schedule-task-scroll'));
    await tester.ensureVisible(source);
    await tester.pumpAndSettle();
    final state = tester.state<ScrollableState>(
        find.ancestor(of: source, matching: find.byType(Scrollable)).first);
    final before = state.position.pixels;
    final viewport = state.context.findRenderObject() as RenderBox;
    final edge = viewport.localToGlobal(
        Offset(viewport.size.width / 2, viewport.size.height - 16));
    final gesture = await tester.startGesture(tester.getCenter(source));
    await tester.pump(const Duration(milliseconds: 350));
    await gesture.moveBy(const Offset(8, 8));
    await gesture.moveTo(edge);
    await tester.pump(const Duration(milliseconds: 800));
    expect(state.position.pixels, greaterThan(before + 200));
    // Re-evaluate the hour after the scroll, then finish the drag.
    await gesture.moveBy(const Offset(1, -2));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(store.tasks.single.blockStart, isNotNull);
    expect(store.tasks.single.blockStart!.hour, greaterThan(3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
