import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grit/design.dart';
import 'package:grit/domain.dart';
import 'package:grit/main.dart';
import 'package:grit/platform_bridge.dart';
import 'package:grit/store.dart';

void main() {
  testWidgets(
      'Today empty action opens capture and first task removes empty state',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = GritStore();
    await store.init(enableCloud: false);
    store.onboarded = true;
    await tester.pumpWidget(GritApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('A little breathing room.'), findsOneWidget);
    await tester.ensureVisible(find.text('Plan a task'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan a task'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close editor'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'My first step');
    await tester.tap(find.text('Add task').last);
    await tester.pumpAndSettle();
    expect(store.tasks.single.title, 'My first step');
    expect(store.tasks.single.scheduled, isNotNull);
    expect(find.byType(GritEmptyState), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('empty state stays usable at 3x text in light and OLED',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    var actions = 0;
    for (final dark in [false, true]) {
      await tester.pumpWidget(MaterialApp(
          theme:
              ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: Scaffold(
              backgroundColor: dark ? Colors.black : Colors.white,
              body: SingleChildScrollView(
                  child: GritEmptyState(
                      title: 'Give this project a first step.',
                      message:
                          'Start with one manageable task. Organize it as your plan grows.',
                      actionLabel: 'Add first task',
                      onAction: () => actions++)))));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add first task'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add first task'));
      expect(tester.takeException(), isNull);
    }
    expect(actions, 2);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('native widget snapshot respects Today, snoozes and parent tasks',
      (tester) async {
    widgetBridgeOverride = true;
    addTearDown(() => widgetBridgeOverride = null);
    Map<dynamic, dynamic>? snapshot;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(platformBridge, (call) async {
      if (call.method == 'updateWidget') snapshot = call.arguments as Map;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(platformBridge, null));
    final today = day(DateTime.now());
    await updateTodayWidget([
      Task(id: 'today', title: 'Today', scheduled: today),
      Task(
          id: 'overdue',
          title: 'Overdue',
          scheduled: today.subtract(const Duration(days: 1))),
      Task(
          id: 'future',
          title: 'Future',
          scheduled: today.add(const Duration(days: 1))),
      Task(id: 'child', title: 'Child', scheduled: today, parentId: 'today'),
      Task(
          id: 'snoozed',
          title: 'Snoozed',
          scheduled: today,
          snoozedUntil: today.add(const Duration(days: 1))),
      Task(id: 'done', title: 'Done', scheduled: today, doneAt: DateTime.now()),
    ], workspace: 'test-owner');
    expect(snapshot!['workspace'], 'test-owner');
    expect(
        (snapshot!['tasks'] as List).map((t) => t['id']), ['today', 'overdue']);
  },
      variant:
          TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}));
}
