// Browser file picker kept behind a conditional import.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

Future<Map<String, dynamic>?> pickAttachment() async {
  final input = html.FileUploadInputElement()..accept = '*/*';
  final result = Completer<Map<String, dynamic>?>();
  input.onChange.first.then((_) async {
    final file = input.files?.firstOrNull;
    if (file == null) {
      result.complete(null);
      return;
    }
    if (file.size > 1024 * 1024) {
      result.completeError(const FormatException('Choose a file up to 1 MB.'));
      return;
    }
    final reader = html.FileReader()..readAsDataUrl(file);
    await reader.onLoadEnd.first;
    if (reader.result is! String) {
      result.completeError(const FormatException('Could not read this file.'));
      return;
    }
    final data = (reader.result as String).split(',').last;
    result.complete({
      'name': file.name,
      'mime': file.type,
      'size': file.size,
      'data': data
    });
  });
  input.addEventListener('cancel', (_) {
    if (!result.isCompleted) result.complete(null);
  });
  input.click();
  return result.future;
}

Future<void> downloadFile(String name, Uint8List bytes, String mime) async {
  final url = 'data:$mime;base64,${base64Encode(bytes)}';
  html.AnchorElement(href: url)
    ..download = name
    ..click();
}
