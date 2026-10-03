import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grit/domain.dart';
import 'package:grit/main.dart';
import 'package:grit/native_ui.dart';
import 'package:grit/platform_bridge.dart';
import 'package:grit/store.dart';

Future<GritStore> planner() async {
  SharedPreferences.setMockInitialValues({});
  final s = GritStore();
  await s.init(enableCloud: false);
  s.onboarded = true;
  s.tasks = [
    Task(
        id: 'task',
        title: 'Read the next chapter',
        scheduled: day(DateTime.now()))
  ];
  return s;
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('native tabs, swipe completion, undo and long press actions',
      (tester) async {
    phone(tester);
    final s = await planner();
    await tester.pumpWidget(GritApp(store: s));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoSliverNavigationBar), findsOneWidget);
    expect(find.byType(CupertinoTabBar), findsOneWidget);
    await tester.ensureVisible(find.byType(SwipeTaskActions).first);
    await tester.pumpAndSettle();
    await tester.drag(
        find.byType(SwipeTaskActions).first, const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(s.tasks.single.done(DateTime.now()), isTrue);
    await tester.tap(find.text('Undo').last);
    await tester.pumpAndSettle();
    expect(s.tasks.single.done(DateTime.now()), isFalse);
    await tester.ensureVisible(find.text('Read the next chapter'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Read the next chapter'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(CupertinoActionSheet),
            matching: find.text('Schedule')),
        findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upcoming').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('left swipe reveals schedule and trash with undo',
      (tester) async {
    phone(tester);
    final s = await planner();
    await tester.pumpWidget(GritApp(store: s));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(SwipeTaskActions).first);
    await tester.pumpAndSettle();
    await tester.drag(
        find.byType(SwipeTaskActions).first, const Offset(-130, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.trash).first);
    await tester.pumpAndSettle();
    expect(s.tasks.single.trashed, isTrue);
    await tester.tap(find.text('Undo').last);
    await tester.pumpAndSettle();
    expect(s.tasks.single.trashed, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('phone task capture uses a native sheet and priority haptics',
      (tester) async {
    phone(tester);
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(GritApp(store: await planner()));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(ModalRoute.of(tester.element(find.text('Priority 4'))),
        isA<GritSheetRoute>());
    await tester.tap(find.text('Priority 4'));
    await tester.pumpAndSettle();
    expect(find.text('Priority 1'), findsOneWidget);
    expect(haptics, contains('HapticFeedbackType.selectionClick'));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('capture sheet dismisses with a downward drag', (tester) async {
    phone(tester);
    await tester.pumpWidget(GritApp(store: await planner()));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    // Drag the sheet chrome, away from its scrollable text fields.
    final editor = find.byTooltip('Close editor');
    final point = tester.getCenter(editor) + const Offset(-90, -20);
    await tester.dragFrom(point, const Offset(0, 650));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close editor'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'accessibility text scaling is inherited and Today remains usable',
      (tester) async {
    phone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(GritApp(store: await planner()));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('Read the next chapter'));
    expect(MediaQuery.textScalerOf(context).scale(17), 34);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('system appearance and OLED preference survive restore',
      (tester) async {
    final s = await planner();
    s.oledBlack = true;
    await s.save();
    final restored = GritStore();
    await restored.init(enableCloud: false);
    expect(restored.appearance, 'System');
    expect(restored.oledBlack, isTrue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(GritApp(store: restored));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(CupertinoTabBar));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(Theme.of(context).scaffoldBackgroundColor, Colors.black);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'largest accessibility text fits onboarding, settings and capture',
      (tester) async {
    phone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final s = await planner();
    s.onboarded = false;
    await tester.pumpWidget(GritApp(store: s));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'Onboarding');
    s.onboarded = true;
    await s.save();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'Today');
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'Settings');
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'Capture');
    await tester.ensureVisible(find.text('More details'));
    await tester.tap(find.text('More details'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'Expanded capture');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('reduced motion checkbox does not leave an animation running',
      (tester) async {
    var checked = false;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: StatefulBuilder(builder: (c, set) {
              update = set;
              return SpringCheck(checked: checked, color: Colors.green);
            }))));
    update(() => checked = true);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(find.byIcon(CupertinoIcons.check_mark), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('widget queue is durable, account scoped and replay safe',
      (tester) async {
    widgetBridgeOverride = true;
    addTearDown(() => widgetBridgeOverride = null);
    final queue = <Map<String, dynamic>>[];
    var acknowledgements = 0;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(platformBridge, (call) async {
      if (call.method == 'widgetCompletions') return queue;
      if (call.method == 'ackWidgetCompletions') {
        final prefs = await SharedPreferences.getInstance();
        final saved = jsonDecode(prefs.getString('grit.v1.local')!);
        if (acknowledgements < 2) {
          expect(saved['tasks'][0]['doneAt'], isNotNull);
        }
        acknowledgements++;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(platformBridge, null));
    final s = await planner();
    queue.add({
      'id': 'completion',
      'taskId': 'task',
      'workspace': s.cacheKey,
      'scheduled': s.tasks.single.scheduled!.toIso8601String(),
      'at': DateTime.now().toUtc().toIso8601String()
    });
    await s.consumeWidgetCompletions();
    final first = s.tasks.single.doneAt;
    await s.consumeWidgetCompletions();
    expect(s.tasks.single.doneAt, first);
    expect(acknowledgements, 2);
    queue.single['workspace'] = 'grit.v1.someone-else';
    s.tasks.single.doneAt = null;
    await s.consumeWidgetCompletions();
    expect(s.tasks.single.doneAt, isNull);
    expect(acknowledgements, 2);
    queue.single['workspace'] = s.cacheKey;
    queue.single['scheduled'] = '2020-01-01T00:00:00.000';
    await s.consumeWidgetCompletions();
    expect(s.tasks.single.doneAt, isNull);
    expect(acknowledgements, 3);
    queue.clear();
  },
      variant:
          TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}));
}
