import 'package:flutter/material.dart';
import 'design.dart';

/// A factual day summary: completion is independent of optional gamification.
class DayOverview extends StatelessWidget {
  const DayOverview(
      {super.key,
      required this.remaining,
      required this.completed,
      required this.minutes,
      required this.onFocus,
      required this.onPlan});
  final int remaining, completed, minutes;
  final VoidCallback? onFocus;
  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) {
    final total = remaining + completed;
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF242F32),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF3E4C4E)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('YOUR DAY, AT A GLANCE',
                    style: TextStyle(
                        color: Color(0xFFB8CEC7),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.7)),
                const SizedBox(height: 12),
                Text(
                    remaining == 0
                        ? 'Room to breathe.'
                        : 'One thing at a time.',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        height: 1.12,
                        letterSpacing: -.8,
                        fontWeight: FontWeight.w600)),
              ])),
          const SizedBox(width: 14),
          Semantics(
              label: '$completed of $total tasks complete',
              child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Stack(alignment: Alignment.center, children: [
                    CircularProgressIndicator(
                        value: total == 0 ? 0 : completed / total,
                        strokeWidth: 4,
                        color: const Color(0xFFBED4B1),
                        backgroundColor: Colors.white12),
                    Text('$completed',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                  ]))),
        ]),
        const SizedBox(height: 18),
        Text(
            '$remaining remaining  ·  ${minutes >= 60 ? '${minutes ~/ 60}h ${minutes % 60}m' : '${minutes}m'} planned',
            style: const TextStyle(color: Color(0xFFCDD6D3), fontSize: 13)),
        const SizedBox(height: 18),
        Wrap(spacing: 10, runSpacing: 8, children: [
          if (onFocus != null)
            FilledButton.icon(
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    backgroundColor: const Color(0xFFD9E7CE),
                    foregroundColor: const Color(0xFF242F32),
                    minimumSize: const Size(0, 44)),
                onPressed: onFocus,
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('Start focus')),
          TextButton.icon(
              style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 44)),
              onPressed: onPlan,
              icon: const Icon(Icons.calendar_view_day_outlined, size: 17),
              label: const Text('Plan my day')),
        ]),
      ]),
    );
  }
}

class ProjectProgressCard extends StatelessWidget {
  const ProjectProgressCard(
      {super.key,
      required this.name,
      required this.color,
      required this.done,
      required this.total,
      required this.onTap});
  final String name;
  final Color color;
  final int done, total;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: surface(context),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: hairline(context))),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.folder_outlined, color: color, size: 21),
                      const Spacer(),
                      Semantics(
                          label: '$done of $total project tasks complete',
                          child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                  value: total == 0 ? 0 : done / total,
                                  strokeWidth: 3,
                                  color: color,
                                  backgroundColor:
                                      color.withValues(alpha: .12)))),
                      const SizedBox(width: 12),
                      Icon(Icons.arrow_forward_rounded,
                          size: 16, color: secondary(context))
                    ]),
                    const SizedBox(height: 18),
                    Text(name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text('${total - done} tasks left',
                        style:
                            TextStyle(fontSize: 12, color: secondary(context))),
                    const SizedBox(height: 14),
                    ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                            value: total == 0 ? 0 : done / total,
                            color: color,
                            backgroundColor: color.withValues(alpha: .12),
                            minHeight: 4)),
                  ])),
        ),
      );
}
