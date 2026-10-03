import 'package:flutter/services.dart';

const _bridge = MethodChannel('grit/platform');
Future<Map<String, dynamic>?> pickAttachment() async {
  final value =
      await _bridge.invokeMapMethod<String, dynamic>('pickAttachment');
  return value;
}

Future<void> downloadFile(String name, Uint8List bytes, String mime) async {
  await _bridge
      .invokeMethod('saveFile', {'name': name, 'bytes': bytes, 'mime': mime});
}
