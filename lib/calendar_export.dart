import 'dart:convert';
import 'domain.dart';

String _icalText(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll('\n', '\\n')
    .replaceAll(';', '\\;')
    .replaceAll(',', '\\,')
    .replaceAll('\r', '');
String _stamp(DateTime d) {
  final u = d.toUtc();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${u.year}${pad(u.month)}${pad(u.day)}T${pad(u.hour)}${pad(u.minute)}${pad(u.second)}Z';
}

String _fold(String line) {
  final lines = <String>[];
  var segment = '';
  var size = 0;
  for (final rune in line.runes) {
    final char = String.fromCharCode(rune), length = utf8.encode(char).length;
    if (size + length > 75) {
      lines.add(segment);
      segment = ' ';
      size = 1;
    }
    segment += char;
    size += length;
  }
  lines.add(segment);
  return lines.join('\r\n');
}

String calendarExport(Iterable<Task> tasks, {DateTime? generated}) {
  final lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//GRIT//Planner//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH'
  ];
  for (final t in tasks.where((t) => !t.trashed && t.blockStart != null)) {
    lines.addAll([
      'BEGIN:VEVENT',
      'UID:${_icalText(t.id)}@grit.local',
      'DTSTAMP:${_stamp(generated ?? DateTime.now())}',
      'DTSTART:${_stamp(t.blockStart!)}',
      'DTEND:${_stamp(t.blockStart!.add(Duration(minutes: t.minutes)))}',
      'SUMMARY:${_icalText(t.title)}',
      'DESCRIPTION:${_icalText(t.notes)}',
      'END:VEVENT'
    ]);
  }
  lines.add('END:VCALENDAR');
  return '${lines.map(_fold).join('\r\n')}\r\n';
}
