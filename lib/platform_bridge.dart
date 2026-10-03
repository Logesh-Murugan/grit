import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/services.dart';
import 'domain.dart';
import 'widget_runtime_native.dart'
    if (dart.library.html) 'widget_runtime_web.dart';

const platformBridge = MethodChannel('grit/platform');
bool get hasAndroidBridge =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
bool get hasIOSBridge => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
bool get hasNativeBridge => hasAndroidBridge || hasIOSBridge;
// A target-platform theme override does not install native widget channels.
@visibleForTesting
bool? widgetBridgeOverride;
bool get hasWidgetBridge => widgetBridgeOverride ?? widgetRuntimeSupported;
Future<void> updateTodayWidget(Iterable<Task> tasks,
    {String workspace = 'grit.v1.local'}) async {
  if (!hasWidgetBridge) return;
  try {
    final now = DateTime.now();
    final today = day(now);
    final visible = tasks.where((t) =>
        t.parentId == null &&
        !t.done(now) &&
        !t.trashed &&
        (t.category == Category.habit ||
            t.pinnedDay == dayKey(now) ||
            (t.scheduled != null && !day(t.scheduled!).isAfter(today))) &&
        (t.snoozedUntil == null || !t.snoozedUntil!.isAfter(now)));
    await platformBridge.invokeMethod('updateWidget', {
      'workspace': workspace,
      'day': dayKey(now),
      'tasks': visible.map((t) => t.toJson()).toList()
    });
  } on PlatformException catch (_) {
  } on MissingPluginException catch (_) {
  } on FlutterError catch (_) {
    // A store can also run without a Flutter binding, for example in unit tests.
  }
}

Future<List<Map<String, dynamic>>> readWidgetCompletions() async {
  if (!hasWidgetBridge) return [];
  try {
    final values =
        await platformBridge.invokeListMethod<dynamic>('widgetCompletions');
    return (values ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  } on PlatformException catch (_) {
    return [];
  } on MissingPluginException catch (_) {
    return [];
  } on FlutterError catch (_) {
    // Domain-only tests and tools can create a store without a Flutter binding.
    return [];
  }
}

Future<void> acknowledgeWidgetCompletions(List<String> ids) async {
  if (!hasWidgetBridge || ids.isEmpty) return;
  await platformBridge.invokeMethod('ackWidgetCompletions', ids);
}
