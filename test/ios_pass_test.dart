import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grit/design.dart';
import 'package:grit/domain.dart';
import 'package:grit/main.dart';
import 'package:grit/store.dart';
import 'package:grit/ios_surfaces.dart';

Future<GritStore> fixture() async {
  SharedPreferences.setMockInitialValues({});
  final store = GritStore();
  await store.init(enableCloud: false);
  store.onboarded = true;
  store.tasks = [
    Task(
        id: 'one',
        title: 'A meaningful next step',
        scheduled: day(DateTime.now()),
        fields: [TaskField('Course', 'Text', 'Backend')])
  ];
  return store;
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
      'completion haptic is immediate, row collapses and Undo restores it',
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
    final store = await fixture();
    await tester.pumpWidget(GritApp(store: store));
    await tester.pumpAndSettle();
    final row = find.byType(TaskCompletionMotion);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    final height = tester.getSize(row).height;
    await tester.tap(find.byTooltip('Complete A meaningful next step'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(haptics, contains('HapticFeedbackType.lightImpact'));
    expect(store.tasks.single.done(DateTime.now()), isFalse);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(row).height, lessThan(height));
    await tester.pumpAndSettle();
    expect(store.tasks.single.done(DateTime.now()), isTrue);
    await tester.tap(find.text('Undo').last);
    await tester.pumpAndSettle();
    expect(store.tasks.single.done(DateTime.now()), isFalse);
    expect(find.text('A meaningful next step'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'phone detail sheet keeps completion reachable at 3x in light dark and OLED',
      (tester) async {
    phone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = await fixture();
    await tester.pumpWidget(GritApp(store: store));
    for (final mode in ['Light', 'Dark', 'OLED']) {
      store.appearance = mode == 'Light' ? 'Light' : 'Dark';
      store.oledBlack = mode == 'OLED';
      await store.save();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('A meaningful next step'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A meaningful next step'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailShell), findsOneWidget);
      final button = find
          .ancestor(
              of: find.text('Complete task'),
              matching:
                  find.byWidgetPredicate((widget) => widget is FilledButton))
          .first;
      final bounds = tester.getRect(button);
      expect(bounds.bottom, lessThanOrEqualTo(844));
      expect(bounds.top, greaterThan(0));
      expect(
          MediaQuery.textScalerOf(tester.element(find.text('Task details')))
              .scale(17),
          51);
      if (mode == 'OLED') {
        expect(Theme.of(tester.element(button)).scaffoldBackgroundColor,
            Colors.black);
      }
      await tester.tap(find.byTooltip('Close details'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: mode);
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('small colored label text meets contrast across appearances',
      (tester) async {
    final store = await fixture();
    for (final dark in [false, true]) {
      final theme = GritApp(store: store).theme(dark);
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Builder(builder: (c) {
            context = c;
            return const Scaffold();
          })));
      for (final color in [
        accent,
        sage,
        violet,
        ...List.generate(4, (i) => priorityColor(i + 1))
      ]) {
        final background =
            Color.alphaBlend(color.withValues(alpha: .08), surface(context));
        final text = legibleColor(context, color, background: background);
        final a = text.computeLuminance(), b = background.computeLuminance();
        expect(a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05),
            greaterThanOrEqualTo(4.5));
      }
    }
  });
}
