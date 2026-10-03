import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grit/timed_notice.dart';

void main() {
  for (final accessible in [false, true]) {
    testWidgets('Undo notice expires with accessible navigation $accessible',
        (tester) async {
      final notice = TimedNotice();
      addTearDown(notice.dispose);
      late BuildContext host;
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
        data: MediaQueryData(accessibleNavigation: accessible),
        child: Scaffold(body: Builder(builder: (context) {
          host = context;
          return const SizedBox();
        })),
      )));
      notice.show(host, 'Scheduled at 01:00',
          action: SnackBarAction(label: 'Undo', onPressed: () {}));
      await tester.pumpAndSettle();
      expect(find.text('Scheduled at 01:00'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Scheduled at 01:00'), findsNothing);
      expect(find.text('Undo'), findsNothing);
    });
  }
  testWidgets('replacement resets expiry; close and navigation dismiss safely',
      (tester) async {
    final notice = TimedNotice();
    addTearDown(notice.dispose);
    late BuildContext host;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) {
        host = context;
        return const SizedBox();
      }),
    )));
    notice.show(host, 'First');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    notice.show(host, 'Second');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsNothing);
    notice.show(host, 'Third');
    await tester.pumpAndSettle();
    notice.dismiss();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
