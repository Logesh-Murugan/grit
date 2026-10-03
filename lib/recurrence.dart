import 'domain.dart';

/// Validated calendar-day RRULE subset. Unsupported clauses are rejected.
class RecurrenceRule {
  RecurrenceRule._(this.parts);
  final Map<String, String> parts;
  static const weekdays = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
  factory RecurrenceRule.parse(String raw) {
    raw = {
          'daily': 'FREQ=DAILY',
          'weekdays': 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR',
          'weekly': 'FREQ=WEEKLY',
          'monthly': 'FREQ=MONTHLY'
        }[raw] ??
        raw.toUpperCase().replaceFirst('RRULE:', '');
    final parts = <String, String>{};
    for (final clause in raw.split(';')) {
      final pair = clause.split('=');
      if (pair.length != 2 || parts.containsKey(pair[0])) {
        throw const FormatException('Use a valid RRULE with unique clauses.');
      }
      parts[pair[0]] = pair[1];
    }
    const supported = {
      'FREQ',
      'INTERVAL',
      'BYDAY',
      'BYMONTHDAY',
      'BYMONTH',
      'COUNT',
      'UNTIL',
      'WKST'
    };
    if (parts.keys.any((k) => !supported.contains(k)) ||
        !{'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'}.contains(parts['FREQ'])) {
      throw const FormatException(
          'Supported: DAILY, WEEKLY, MONTHLY, YEARLY with INTERVAL, BYDAY, BYMONTHDAY, BYMONTH, COUNT, UNTIL, WKST.');
    }
    for (final key in ['INTERVAL', 'COUNT']) {
      if (parts.containsKey(key) &&
          (int.tryParse(parts[key]!) == null ||
              int.parse(parts[key]!) < 1 ||
              int.parse(parts[key]!) > 10000)) {
        throw FormatException('$key must be between 1 and 10000.');
      }
    }
    if (parts.containsKey('COUNT') && parts.containsKey('UNTIL')) {
      throw const FormatException('Choose COUNT or UNTIL, not both.');
    }
    for (final key in ['BYMONTHDAY', 'BYMONTH']) {
      if (parts.containsKey(key)) {
        for (final n in parts[key]!.split(',')) {
          final v = int.tryParse(n);
          if (v == null ||
              v == 0 ||
              (key == 'BYMONTH' ? v < 1 || v > 12 : v.abs() > 31)) {
            throw FormatException('Invalid $key.');
          }
        }
      }
    }
    if (parts.containsKey('BYMONTHDAY') && parts['FREQ'] == 'WEEKLY') {
      throw const FormatException('BYMONTHDAY is not valid for weekly rules.');
    }
    if (parts.containsKey('BYDAY')) {
      for (final token in parts['BYDAY']!.split(',')) {
        final match =
            RegExp(r'^([+-]?[1-5])?(MO|TU|WE|TH|FR|SA|SU)$').firstMatch(token);
        if (match == null ||
            (match[1] != null &&
                (!{'MONTHLY', 'YEARLY'}.contains(parts['FREQ']) ||
                    (parts['FREQ'] == 'YEARLY' &&
                        !parts.containsKey('BYMONTH'))))) {
          throw const FormatException(
              'Use weekday codes such as MO,WE,FR; ordinals like 1MO apply to months.');
        }
      }
    }
    if (parts.containsKey('WKST') && !weekdays.contains(parts['WKST'])) {
      throw const FormatException('WKST must be a weekday code.');
    }
    if (parts.containsKey('UNTIL')) _until(parts['UNTIL']!);
    return RecurrenceRule._(parts);
  }
  static DateTime _until(String s) {
    if (!RegExp(r'^\d{8}(T\d{6}Z?)?$').hasMatch(s)) {
      throw const FormatException(
          'UNTIL must be YYYYMMDD or YYYYMMDDTHHMMSSZ.');
    }
    final y = int.parse(s.substring(0, 4)),
        m = int.parse(s.substring(4, 6)),
        d = int.parse(s.substring(6, 8));
    final h = s.length > 8 ? int.parse(s.substring(9, 11)) : 23;
    final min = s.length > 8 ? int.parse(s.substring(11, 13)) : 59;
    final sec = s.length > 8 ? int.parse(s.substring(13, 15)) : 59;
    final value = s.endsWith('Z')
        ? DateTime.utc(y, m, d, h, min, sec)
        : DateTime(y, m, d, h, min, sec);
    if (value.year != y ||
        value.month != m ||
        value.day != d ||
        h > 23 ||
        min > 59 ||
        sec > 59) {
      throw const FormatException('Invalid UNTIL date.');
    }
    return value;
  }

  bool matches(DateTime d, DateTime anchor) {
    final interval = int.parse(parts['INTERVAL'] ?? '1');
    final days = DateTime.utc(d.year, d.month, d.day)
        .difference(DateTime.utc(anchor.year, anchor.month, anchor.day))
        .inDays;
    if (days < 0) return false;
    switch (parts['FREQ']) {
      case 'DAILY':
        if (days % interval != 0) return false;
      case 'WEEKLY':
        final wk = weekdays.indexOf(parts['WKST'] ?? 'MO') + 1;
        final first = DateTime.utc(anchor.year, anchor.month,
            anchor.day - ((anchor.weekday - wk + 7) % 7));
        final diff =
            DateTime.utc(d.year, d.month, d.day).difference(first).inDays ~/ 7;
        if (diff % interval != 0 ||
            (!parts.containsKey('BYDAY') && d.weekday != anchor.weekday)) {
          return false;
        }
      case 'MONTHLY':
        if (((d.year - anchor.year) * 12 + d.month - anchor.month) % interval !=
            0) {
          return false;
        }
      case 'YEARLY':
        if ((d.year - anchor.year) % interval != 0 ||
            (!parts.containsKey('BYMONTH') && d.month != anchor.month)) {
          return false;
        }
    }
    if (parts.containsKey('BYMONTH') &&
        !parts['BYMONTH']!.split(',').map(int.parse).contains(d.month)) {
      return false;
    }
    if (parts.containsKey('BYMONTHDAY')) {
      final last = DateTime(d.year, d.month + 1, 0).day;
      if (!parts['BYMONTHDAY']!
          .split(',')
          .map(int.parse)
          .map((v) => v < 0 ? last + v + 1 : v)
          .contains(d.day)) {
        return false;
      }
    }
    if (parts.containsKey('BYDAY')) {
      final last = DateTime(d.year, d.month + 1, 0).day;
      final ok = parts['BYDAY']!.split(',').any((token) {
        final code = token.substring(token.length - 2);
        if (weekdays[d.weekday - 1] != code) return false;
        final ordinal = token.substring(0, token.length - 2);
        if (ordinal.isEmpty) return true;
        final n = int.parse(ordinal);
        return n > 0
            ? (d.day - 1) ~/ 7 + 1 == n
            : -((last - d.day) ~/ 7 + 1) == n;
      });
      if (!ok) return false;
    }
    if ({'MONTHLY', 'YEARLY'}.contains(parts['FREQ']) &&
        !parts.containsKey('BYDAY') &&
        !parts.containsKey('BYMONTHDAY') &&
        d.day != anchor.day) {
      return false;
    }
    return true;
  }

  DateTime? next(DateTime anchor, DateTime after, {DateTime? notBefore}) {
    final limit = parts.containsKey('UNTIL') ? _until(parts['UNTIL']!) : null;
    final count =
        parts.containsKey('COUNT') ? int.parse(parts['COUNT']!) : null;
    var occurrences = 1; // DTSTART is the first occurrence.
    for (var i = 1; i <= 366 * 200; i++) {
      final d = DateTime(anchor.year, anchor.month, anchor.day + i, anchor.hour,
          anchor.minute, anchor.second);
      if (limit != null && d.isAfter(limit)) return null;
      if (!matches(d, anchor)) continue;
      occurrences++;
      if (count != null && occurrences > count) return null;
      if (d.isAfter(after) &&
          (notBefore == null || !day(d).isBefore(day(notBefore)))) {
        return d;
      }
    }
    throw const FormatException(
        'No occurrence found within the supported 200-year horizon.');
  }
}

DateTime? nextTaskOccurrence(Task t, DateTime now) {
  final from = t.scheduled ?? day(now);
  t.recurrenceAnchor ??= from;
  if (t.recurrence == 'monthly') {
    var candidate = from;
    do {
      final last = DateTime(candidate.year, candidate.month + 2, 0).day;
      candidate = DateTime(candidate.year, candidate.month + 1,
          t.recurrenceAnchor!.day.clamp(1, last), from.hour, from.minute);
    } while (day(candidate).isBefore(day(now)));
    return candidate;
  }
  return RecurrenceRule.parse(t.recurrence)
      .next(t.recurrenceAnchor!, from, notBefore: now);
}
