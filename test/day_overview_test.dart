import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grit/day_overview.dart';

void main() {
  testWidgets('day overview actions, honest empty state and large text',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var focused = false;
    var planned = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DayOverview(
                remaining: 2,
                completed: 1,
                minutes: 90,
                onFocus: () => focused = true,
                onPlan: () => planned = true))));
    expect(find.text('2 remaining  ·  1h 30m planned'), findsOneWidget);
    await tester.tap(find.text('Start focus'));
    await tester.tap(find.text('Plan my day'));
    expect(focused && planned, isTrue);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(3)),
            child: Scaffold(
                body: SingleChildScrollView(
                    child: DayOverview(
                        remaining: 0,
                        completed: 0,
                        minutes: 0,
                        onFocus: null,
                        onPlan: () {}))))));
    expect(find.text('Start focus'), findsNothing);
    expect(find.text('Room to breathe.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
