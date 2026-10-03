import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grit/main.dart';
import 'package:grit/store.dart';
import 'package:grit/showcase.dart';
import 'package:grit/domain.dart';
import 'package:grit/workspace.dart';

void main() {
  testWidgets('onboarding and all workspace views fit a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final s = GritStore();
    await s.init();
    await tester.pumpWidget(GritApp(store: s));
    await tester.ensureVisible(find.text('Explore a sample workspace'));
    await tester.tap(find.text('Explore a sample workspace'));
    await tester.pumpAndSettle();
    expect(find.textContaining('A fresh page'), findsNothing);
    expect(tester.takeException(), isNull);
    for (final v in ['Upcoming', 'Inbox']) {
      await tester.tap(find.text(v).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: v);
    }
    for (final v in [
      'Filters & labels',
      'Productivity',
      'Habits',
      'Events',
      'Activity',
      'Completed'
    ]) {
      await tester.tap(find.byTooltip('Open navigation'));
      await tester.pumpAndSettle();
      final item =
          find.descendant(of: find.byType(Drawer), matching: find.text(v));
      await tester.scrollUntilVisible(item, 140,
          scrollable: find
              .descendant(
                  of: find.byType(Drawer), matching: find.byType(Scrollable))
              .first);
      await tester.ensureVisible(item);
      await tester.pumpAndSettle();
      await tester.tap(item.hitTestable());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: v);
    }
    await tester.tap(find.byTooltip('Settings').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('natural quick capture, detail and completion persist',
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
    await tester.enterText(
        find.byType(TextField).first, 'Submit physics lab today p1 @study');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Add task'));
    await tester.tap(find.widgetWithText(FilledButton, 'Add task'));
    await tester.pumpAndSettle();
    expect(s.tasks.single.title, 'Submit physics lab');
    expect(s.tasks.single.priority, 1);
    expect(s.tasks.single.labels, ['study']);
    await tester.ensureVisible(find.text('Submit physics lab'));
    await tester.ensureVisible(find.text('Submit physics lab'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit physics lab'));
    await tester.pumpAndSettle();
    expect(find.text('Comments & notes'), findsOneWidget);
    await tester.ensureVisible(find.text('Complete task'));
    await tester.tap(find.text('Complete task'));
    await tester.pumpAndSettle();
    expect(s.tasks.single.done(DateTime.now()), true);
    final restored = GritStore();
    await restored.init();
    expect(restored.tasks.single.done(DateTime.now()), true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('desktop has project navigation and all four task layouts',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final s = GritStore();
    await s.init();
    loadShowcase(s);
    await tester.pumpWidget(GritApp(store: s));
    await tester.pumpAndSettle();
    expect(find.text('A little room to focus'), findsOneWidget);
    for (final v in ['Board', 'Calendar', 'Schedule', 'List']) {
      await tester.tap(find.text(v).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: v);
    }
    await tester.tap(find.byTooltip('Settings').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('System').first);
    await tester.tap(find.text('System').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();
    expect(s.darkMode, true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('expanded editor fits phone and short viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 700);
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
    await tester.tap(find.text('More details'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test('freeze cannot be reused in the same week', () async {
    SharedPreferences.setMockInitialValues({});
    final s = GritStore();
    await s.init();
    expect(s.freezeYesterday(), true);
    expect(s.freezeYesterday(), false);
  });
  test('completed effort is deducted from capacity', () async {
    SharedPreferences.setMockInitialValues({});
    final s = GritStore();
    await s.init();
    s.capacity = 60;
    s.tasks = [Task(id: 'x', title: 'x', minutes: 45, doneAt: DateTime.now())];
    expect(s.remainingCapacity, 15);
  });
}
