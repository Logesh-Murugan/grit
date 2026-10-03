import 'domain.dart';

class Project {
  Project(
      {required this.id,
      required this.name,
      this.color = 0xFFDF7561,
      this.icon = 'work',
      this.favorite = false,
      this.archived = false,
      this.description = '',
      this.parentId,
      this.order = 0,
      this.view = 'List',
      this.sections = const ['To do', 'In progress', 'Done']});
  final String id;
  String name, icon, description;
  int color;
  bool favorite, archived;
  List<String> sections;
  String? parentId;
  int order;
  String view;
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'icon': icon,
        'favorite': favorite,
        'archived': archived,
        'description': description,
        'sections': sections,
        'parentId': parentId,
        'order': order,
        'view': view
      };
  factory Project.fromJson(Map<String, dynamic> j) => Project(
      id: j['id'],
      name: j['name'],
      color: j['color'] ?? 0xFFDF7561,
      icon: j['icon'] ?? 'work',
      favorite: j['favorite'] ?? false,
      archived: j['archived'] ?? false,
      description: j['description'] ?? '',
      parentId: j['parentId'],
      order: j['order'] ?? 0,
      view: j['view'] ?? 'List',
      sections:
          List<String>.from(j['sections'] ?? ['To do', 'In progress', 'Done']));
}

class SavedFilter {
  SavedFilter(this.id, this.name, this.query, {this.favorite = false});
  String id, name, query;
  bool favorite;
  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'query': query, 'favorite': favorite};
  factory SavedFilter.fromJson(Map<String, dynamic> j) =>
      SavedFilter(j['id'], j['name'], j['query'],
          favorite: j['favorite'] ?? false);
}

/// Small, explicit query grammar. Unsupported terms throw rather than returning
/// misleading results. OR has lower precedence than AND; parentheses nest.
class TaskQuery {
  static bool matches(Task task, String query, DateTime now,
      {String projectName = ''}) {
    final input = query.trim();
    if (input.isEmpty) return true;
    bool eval(String q) {
      q = q.trim();
      if (q.isEmpty) {
        throw const FormatException(
            'Add a condition on both sides of an operator.');
      }
      var depth = 0;
      for (var i = 0; i < q.length; i++) {
        if (q[i] == '(') depth++;
        if (q[i] == ')') depth--;
        if (depth < 0) throw const FormatException('Check your parentheses.');
      }
      if (depth != 0) throw const FormatException('Check your parentheses.');
      for (final op in ['|', '&']) {
        depth = 0;
        for (var i = 0; i < q.length; i++) {
          if (q[i] == '(') depth++;
          if (q[i] == ')') depth--;
          if (depth == 0 && q[i] == op) {
            final a = eval(q.substring(0, i)), b = eval(q.substring(i + 1));
            return op == '|' ? a || b : a && b;
          }
        }
      }
      if (q.startsWith('!')) return !eval(q.substring(1));
      if (q.startsWith('(') && q.endsWith(')')) {
        return eval(q.substring(1, q.length - 1));
      }
      q = q.toLowerCase();
      final scheduled = task.scheduled;
      if (q == 'today') {
        return scheduled != null && dayKey(scheduled) == dayKey(now);
      }
      if (q == 'tomorrow') {
        return scheduled != null &&
            dayKey(scheduled) == dayKey(day(now).add(const Duration(days: 1)));
      }
      if (q == 'overdue') {
        return !task.done(now) &&
            ((scheduled != null && day(scheduled).isBefore(day(now))) ||
                task.overdue(now));
      }
      if (q == 'no date') return scheduled == null;
      if (q == 'no deadline') return task.deadline == null;
      if (q == 'recurring') {
        return task.recurrence.isNotEmpty || task.category == Category.habit;
      }
      if (q == 'subtask') return task.parentId != null;
      if (q == 'completed') return task.done(now);
      if (q == 'view all') return true;
      if (RegExp(r'^p[1-4]$').hasMatch(q)) {
        return task.priority == int.parse(q[1]);
      }
      if (q.startsWith('@') || q.startsWith('%')) {
        return task.labels.any((l) => l.toLowerCase() == q.substring(1));
      }
      if (q.startsWith('#')) return projectName.toLowerCase() == q.substring(1);
      if (q.startsWith('search:')) {
        return '${task.title} ${task.notes}'
            .toLowerCase()
            .contains(q.substring(7).trim());
      }
      if (q == '7 days') {
        return scheduled != null &&
            !day(scheduled).isBefore(day(now)) &&
            day(scheduled).isBefore(day(now).add(const Duration(days: 7)));
      }
      throw FormatException('Unsupported condition: $q');
    }

    return eval(input);
  }
}

class QuickCapture {
  QuickCapture(this.title,
      {this.date,
      this.priority = 4,
      this.hasPriority = false,
      this.labels = const [],
      this.projectName,
      this.recurrence = ''});
  final String title, recurrence;
  final DateTime? date;
  final int priority;
  final bool hasPriority;
  final List<String> labels;
  final String? projectName;
  static QuickCapture parse(String input, DateTime now) {
    var text = input;
    DateTime? date;
    var priority = 4;
    var hasPriority = false;
    var recurrence = '';
    String? project;
    final labels = <String>[];
    text = text.replaceAllMapped(
        RegExp(r'(?<!\S)p([1-4])(?!\S)', caseSensitive: false), (m) {
      priority = int.parse(m[1]!);
      hasPriority = true;
      return '';
    });
    text = text.replaceAllMapped(RegExp(r'(?<!\S)[@%]([\w-]+)'), (m) {
      labels.add(m[1]!);
      return '';
    });
    text =
        text.replaceAllMapped(RegExp(r'(?<!\S)#(?:"([^"]+)"|([\w-]+))'), (m) {
      project = m[1] ?? m[2]!.replaceAll('-', ' ');
      return '';
    });
    for (final r in [
      'every weekday',
      'every day',
      'every week',
      'every month'
    ]) {
      if (text.toLowerCase().contains(r)) {
        recurrence = {
          'every weekday': 'weekdays',
          'every day': 'daily',
          'every week': 'weekly',
          'every month': 'monthly'
        }[r]!;
        text = text.replaceAll(RegExp(r, caseSensitive: false), '');
        date = day(now);
        break;
      }
    }
    final weekdays = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday'
    ];
    final pattern = RegExp(
        r'\b(today|tomorrow|next week|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b',
        caseSensitive: false);
    final match = pattern.firstMatch(text);
    if (match != null) {
      final word = match[0]!.toLowerCase();
      final offset = word == 'today'
          ? 0
          : word == 'tomorrow'
              ? 1
              : word == 'next week'
                  ? 7
                  : ((weekdays.indexOf(word) + 1 - now.weekday + 7) % 7 == 0
                      ? 7
                      : (weekdays.indexOf(word) + 1 - now.weekday + 7) % 7);
      date = day(now).add(Duration(days: offset));
      text = text.replaceRange(match.start, match.end, '');
    }
    final time = RegExp(
            r'\b(?:at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?|(\d{1,2})(?::(\d{2}))?\s*(am|pm))\b',
            caseSensitive: false)
        .firstMatch(text);
    if (time != null) {
      var hour = int.parse(time[1] ?? time[4]!);
      final minute = int.parse(time[2] ?? time[5] ?? '0');
      final suffix = (time[3] ?? time[6])?.toLowerCase();
      if (minute <= 59 &&
          ((suffix != null && hour >= 1 && hour <= 12) ||
              (suffix == null && hour <= 23))) {
        if (suffix == 'pm' && hour < 12) hour += 12;
        if (suffix == 'am' && hour == 12) hour = 0;
        final d = date ?? day(now);
        date = DateTime(d.year, d.month, d.day, hour, minute);
        text = text.replaceRange(time.start, time.end, '');
      }
    }
    return QuickCapture(text.replaceAll(RegExp(r'\s+'), ' ').trim(),
        date: date,
        priority: priority,
        hasPriority: hasPriority,
        labels: labels,
        projectName: project,
        recurrence: recurrence);
  }
}

DateTime nextOccurrence(DateTime from, String rule, DateTime now) {
  var next = from;
  do {
    if (rule == 'monthly') {
      final last = DateTime(next.year, next.month + 2, 0).day;
      next = DateTime(next.year, next.month + 1,
          from.day > last ? last : from.day, next.hour, next.minute);
    } else {
      next = DateTime(next.year, next.month,
          next.day + (rule == 'weekly' ? 7 : 1), next.hour, next.minute);
      if (rule == 'weekdays') {
        while (next.weekday > 5) {
          next = DateTime(
              next.year, next.month, next.day + 1, next.hour, next.minute);
        }
      }
    }
  } while (day(next).isBefore(day(now)));
  return next;
}
