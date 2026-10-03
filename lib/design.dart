import 'package:flutter/material.dart';

const accent = Color(0xFFB64F3C),
    sage = Color(0xFF788A70),
    violet = Color(0xFF8B7DA5),
    ink = Color(0xFF292927);
Color canvas(BuildContext c) => Theme.of(c).scaffoldBackgroundColor;
Color surface(BuildContext c) => Theme.of(c).colorScheme.surface;
Color accentForeground(BuildContext c) =>
    Theme.of(c).brightness == Brightness.dark
        ? const Color(0xFFEC9685)
        : accent;

/// Preserve each tag's hue while keeping small text readable on its surface.
Color legibleColor(BuildContext c, Color color, {Color? background}) {
  final base = background ?? surface(c);
  final target = Theme.of(c).brightness == Brightness.dark ? Colors.white : ink;
  var result = color;
  for (var step = 0; step <= 20; step++) {
    final a = result.computeLuminance(), b = base.computeLuminance();
    final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
    if (ratio >= 4.5) return result;
    result = Color.lerp(color, target, (step + 1) / 21)!;
  }
  return result;
}

Color subtle(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? const Color(0xFF262625)
    : const Color(0xFFF7F7F5);
Color hairline(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? const Color(0xFF383837)
    : const Color(0xFFEDEDE9);
Color secondary(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? const Color(0xFFB4B4BD)
    : const Color(0xFF65656D);
Color priorityColor(int p) => [
      const Color(0xFFD76255),
      const Color(0xFFDCA44A),
      const Color(0xFF7794B6),
      const Color(0xFFB9BBB5)
    ][p.clamp(1, 4) - 1];
String monthName(int n) => [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ][n - 1];
String weekdayName(int n) => [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ][n - 1];
String dateLabel(DateTime d) =>
    '${monthName(d.month).substring(0, 3)} ${d.day}';
String timeLabel(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class GritMark extends StatelessWidget {
  const GritMark({super.key, this.small = false});
  final bool small;
  @override
  Widget build(BuildContext c) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: small ? 26 : 32,
            height: small ? 26 : 32,
            decoration: BoxDecoration(
                color: accent, borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.done_all_rounded,
                size: small ? 17 : 22, color: Colors.white)),
        const SizedBox(width: 9),
        Text('grit',
            // A fixed-size brand mark; all functional content inherits text scaling.
            textScaler: TextScaler.noScaling,
            style: TextStyle(
                fontSize: small ? 23 : 29,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.1))
      ]);
}

class SoftCard extends StatelessWidget {
  const SoftCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(20),
      this.color});
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  @override
  Widget build(BuildContext c) => Container(
      padding: padding,
      decoration: BoxDecoration(
          color: color ?? surface(c),
          border: Border.all(color: hairline(c)),
          borderRadius: BorderRadius.circular(18)),
      child: child);
}

class Pill extends StatelessWidget {
  const Pill(this.text,
      {super.key, this.icon, this.color = accent, this.onTap});
  final String text;
  final IconData? icon;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext c) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
          constraints: BoxConstraints(minHeight: onTap == null ? 0 : 44),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
              color: color.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(7)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: legibleColor(c, color)),
              const SizedBox(width: 5)
            ],
            Flexible(
                child: Text(text,
                    style: TextStyle(
                        color: legibleColor(c, color,
                            background: Color.alphaBlend(
                                color.withValues(alpha: .08), surface(c))),
                        fontSize: 11,
                        fontWeight: FontWeight.w500)))
          ])));
}

class QuietIllustration extends StatelessWidget {
  const QuietIllustration({super.key, this.size = 100});
  final double size;
  @override
  Widget build(BuildContext c) => CustomPaint(
      size: Size(size, size),
      painter: _PlantPainter(dark: Theme.of(c).brightness == Brightness.dark));
}

class _PlantPainter extends CustomPainter {
  _PlantPainter({required this.dark});
  final bool dark;
  @override
  void paint(Canvas c, Size s) {
    c.scale(s.width / 120, s.height / 120);
    final p = Paint()
      ..color = dark ? const Color(0xFF29332D) : const Color(0xFFECEDE3);
    c.drawCircle(const Offset(60, 62), 48, p);
    p.color = dark ? const Color(0xFF4B4139) : const Color(0xFFEEE3D8);
    c.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(37, 79, 47, 22), const Radius.circular(5)),
        p);
    p
      ..color = const Color(0xFF9BA68B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    c.drawLine(const Offset(60, 80), const Offset(60, 30), p);
    p.style = PaintingStyle.fill;
    c.drawOval(const Rect.fromLTWH(37, 35, 23, 13), p);
    c.drawOval(const Rect.fromLTWH(60, 47, 26, 13), p);
    p.color = const Color(0xFFB8C1A8);
    c.drawOval(const Rect.fromLTWH(41, 59, 19, 12), p);
    c.drawOval(const Rect.fromLTWH(60, 25, 19, 12), p);
    p
      ..color = const Color(0xFFCA6651)
      ..strokeWidth = 2;
    c.drawCircle(const Offset(94, 30), 3, p);
    p.color = const Color(0xFFD1C2AC);
    c.drawLine(const Offset(25, 102), const Offset(94, 102), p);
  }

  @override
  bool shouldRepaint(covariant _PlantPainter old) => dark != old.dark;
}

/// A calm, accessible landing point with a concrete next step.
class GritEmptyState extends StatelessWidget {
  const GritEmptyState(
      {super.key,
      required this.title,
      required this.message,
      this.actionLabel,
      this.onAction,
      this.icon = Icons.spa_outlined});
  final String title, message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
      child: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ExcludeSemantics(
                    child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                            color: sage.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(24)),
                        child: Icon(icon,
                            size: 30, color: legibleColor(context, sage)))),
                const SizedBox(height: 20),
                Semantics(
                    header: true,
                    child: Text(title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -.5))),
                const SizedBox(height: 10),
                Text(message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: secondary(context), fontSize: 15, height: 1.5)),
                if (onAction != null && actionLabel != null) ...[
                  const SizedBox(height: 22),
                  FilledButton(onPressed: onAction, child: Text(actionLabel!)),
                ],
              ]))));
}
