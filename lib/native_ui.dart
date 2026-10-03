import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'design.dart';

const gritSpring = SpringDescription(mass: 1, stiffness: 360, damping: 32);
Future<DateTime?> pickGritDate(BuildContext c, DateTime initial,
    {bool withTime = true}) async {
  var selected = initial;
  return showCupertinoModalPopup<DateTime>(
      context: c,
      builder: (sheet) => Material(
          color: surface(sheet),
          child: SafeArea(
              top: false,
              child: SizedBox(
                  height: 330,
                  child: Column(children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          CupertinoButton(
                              onPressed: () => Navigator.pop(sheet),
                              child: const Text('Cancel')),
                          CupertinoButton(
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                Navigator.pop(sheet, selected);
                              },
                              child: const Text('Done'))
                        ]),
                    Expanded(
                        child: CupertinoDatePicker(
                            initialDateTime: initial,
                            mode: withTime
                                ? CupertinoDatePickerMode.dateAndTime
                                : CupertinoDatePickerMode.date,
                            onDateTimeChanged: (value) => selected = value))
                  ])))));
}

bool compactPlatform(BuildContext c) => MediaQuery.sizeOf(c).width < 1000;

Future<T?> gritActions<T>(BuildContext c, String title, Map<T, String> actions,
        {Set<T> destructive = const {}}) =>
    showCupertinoModalPopup<T>(
        context: c,
        builder: (context) => CupertinoActionSheet(
            title: Text(title),
            actions: [
              for (final entry in actions.entries)
                CupertinoActionSheetAction(
                    isDestructiveAction: destructive.contains(entry.key),
                    onPressed: () => Navigator.pop(context, entry.key),
                    child: Text(entry.value))
            ],
            cancelButton: CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'))));

/// Native action-sheet selection on phones, normal dropdown on a wide workspace.
class GritChoiceField<T> extends StatelessWidget {
  const GritChoiceField(
      {super.key,
      required this.initialValue,
      required this.items,
      required this.onChanged,
      this.decoration = const InputDecoration(),
      this.isExpanded = true});
  final T? initialValue;
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final bool isExpanded;
  @override
  Widget build(BuildContext c) {
    if (!compactPlatform(c)) {
      return DropdownButtonFormField<T>(
          initialValue: initialValue,
          items: items,
          onChanged: onChanged,
          decoration: decoration,
          isExpanded: isExpanded);
    }
    return FormField<T>(
        initialValue: initialValue,
        builder: (state) => Semantics(
            button: true,
            child: InkWell(
                onTap: onChanged == null
                    ? null
                    : () async {
                        HapticFeedback.selectionClick();
                        final value = await showCupertinoModalPopup<T>(
                            context: c,
                            builder: (popup) => CupertinoActionSheet(
                                title: Text(
                                    decoration.labelText ?? 'Choose an option'),
                                actions: [
                                  for (final item
                                      in items ?? <DropdownMenuItem<T>>[])
                                    CupertinoActionSheetAction(
                                        onPressed: () =>
                                            Navigator.pop(popup, item.value),
                                        child: DefaultTextStyle.merge(
                                            style:
                                                const TextStyle(fontSize: 17),
                                            child: item.child is Text &&
                                                    (item.child as Text).data !=
                                                        null
                                                ? Text(
                                                    (item.child as Text).data!,
                                                    style: const TextStyle(
                                                        fontSize: 17))
                                                : item.child))
                                ],
                                cancelButton: CupertinoActionSheetAction(
                                    onPressed: () => Navigator.pop(popup),
                                    child: const Text('Cancel'))));
                        if (value != null && c.mounted) {
                          state.didChange(value);
                          onChanged?.call(value);
                        }
                      },
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                    decoration: decoration,
                    child: Row(children: [
                      Expanded(
                          child: (items ?? <DropdownMenuItem<T>>[])
                                  .where((item) => item.value == state.value)
                                  .firstOrNull
                                  ?.child ??
                              const SizedBox()),
                      const SizedBox(width: 8),
                      const Icon(CupertinoIcons.chevron_down, size: 14)
                    ])))));
  }
}

class SpringCheck extends StatefulWidget {
  const SpringCheck({super.key, required this.checked, required this.color});
  final bool checked;
  final Color color;
  @override
  State<SpringCheck> createState() => _SpringCheckState();
}

class GritMenuButton<T> extends StatelessWidget {
  const GritMenuButton(
      {super.key,
      required this.itemBuilder,
      this.onSelected,
      this.icon,
      this.child,
      this.tooltip});
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final Widget? icon, child;
  final String? tooltip;
  @override
  Widget build(BuildContext c) {
    if (!compactPlatform(c)) {
      return PopupMenuButton<T>(
          itemBuilder: itemBuilder,
          onSelected: onSelected,
          icon: icon,
          tooltip: tooltip,
          child: child);
    }
    Future<void> open() async {
      HapticFeedback.selectionClick();
      final entries = itemBuilder(c)
          .whereType<PopupMenuItem<T>>()
          .where((e) => e.enabled)
          .toList();
      final selected = await showCupertinoModalPopup<T>(
          context: c,
          builder: (sheet) => CupertinoActionSheet(
              title: Text(tooltip ?? 'Actions'),
              actions: [
                for (final entry in entries)
                  CupertinoActionSheetAction(
                      onPressed: () => Navigator.pop(sheet, entry.value),
                      child: entry.child ?? const Text('Action'))
              ],
              cancelButton: CupertinoActionSheetAction(
                  onPressed: () => Navigator.pop(sheet),
                  child: const Text('Cancel'))));
      if (selected != null && c.mounted) onSelected?.call(selected);
    }

    if (child != null) {
      return Semantics(
          button: true,
          label: tooltip,
          child: InkWell(onTap: open, child: child));
    }
    return IconButton(
        tooltip: tooltip,
        onPressed: open,
        icon: icon ?? const Icon(CupertinoIcons.ellipsis));
  }
}

class GritSheetRoute<T> extends CupertinoSheetRoute<T> {
  GritSheetRoute({required super.builder, this.reducedMotion = false});
  final bool reducedMotion;
  @override
  Duration get transitionDuration =>
      reducedMotion ? Duration.zero : const Duration(milliseconds: 500);
  @override
  Duration get reverseTransitionDuration => transitionDuration;
  @override
  Simulation? createSimulation({required bool forward}) => reducedMotion
      ? null
      : SpringSimulation(gritSpring, controller?.value ?? (forward ? 0 : 1),
          forward ? 1 : 0, 0);
}

Future<T?> gritSheet<T>(BuildContext c, WidgetBuilder builder) =>
    Navigator.of(c, rootNavigator: true).push(GritSheetRoute<T>(
        reducedMotion: MediaQuery.disableAnimationsOf(c),
        builder: (context) => Material(
            color: surface(context),
            child: SafeArea(top: false, child: builder(context)))));
Future<T?> showGritDetails<T>(
        {required BuildContext context, required WidgetBuilder builder}) =>
    compactPlatform(context)
        ? gritSheet<T>(context, builder)
        : showDialog<T>(context: context, builder: builder);

class SpringLift extends StatefulWidget {
  const SpringLift({super.key, required this.child});
  final Widget child;
  @override
  State<SpringLift> createState() => _SpringLiftState();
}

class _SpringLiftState extends State<SpringLift>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController.unbounded(vsync: this);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.value = 1;
    } else {
      controller
          .animateWith(SpringSimulation(gritSpring, controller.value, 1, 0));
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AnimatedBuilder(
      animation: controller,
      builder: (c, _) => Transform.scale(
          scale: 1 + .025 * controller.value,
          child: Material(
              color: surface(c),
              elevation: 8 * controller.value.clamp(0, 1),
              borderRadius: BorderRadius.circular(12),
              child: widget.child)));
}

class _SpringCheckState extends State<SpringCheck>
    with SingleTickerProviderStateMixin {
  late final controller =
      AnimationController.unbounded(vsync: this, value: widget.checked ? 1 : 0);
  @override
  void didUpdateWidget(SpringCheck old) {
    super.didUpdateWidget(old);
    if (old.checked != widget.checked) {
      final target = widget.checked ? 1.0 : 0.0;
      if (MediaQuery.disableAnimationsOf(context)) {
        controller.value = target;
      } else {
        controller.animateWith(SpringSimulation(
            gritSpring, controller.value, target, controller.velocity));
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AnimatedBuilder(
      animation: controller,
      builder: (c, _) => Transform.scale(
          scale: 1 + .12 * sin(controller.value.clamp(0, 1) * pi),
          child: Container(
              width: 23,
              height: 23,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.lerp(Colors.transparent, widget.color,
                      controller.value.clamp(0, 1)),
                  border: Border.all(color: widget.color, width: 1.5)),
              child: Opacity(
                  opacity: controller.value.clamp(0, 1),
                  child: const Icon(CupertinoIcons.check_mark,
                      size: 14, color: Colors.white)))));
}

class SwipeTaskActions extends StatefulWidget {
  const SwipeTaskActions(
      {super.key,
      required this.child,
      required this.complete,
      required this.schedule,
      required this.delete});
  final Widget child;
  final VoidCallback complete, schedule, delete;
  @override
  State<SwipeTaskActions> createState() => _SwipeTaskActionsState();
}

class _SwipeTaskActionsState extends State<SwipeTaskActions>
    with SingleTickerProviderStateMixin {
  late final x = AnimationController.unbounded(vsync: this);
  double width = 320;
  void settle(double target) {
    if (MediaQuery.disableAnimationsOf(context)) {
      x.value = target;
    } else {
      x.animateWith(SpringSimulation(gritSpring, x.value, target, 0));
    }
  }

  @override
  void dispose() {
    x.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => LayoutBuilder(builder: (c, constraints) {
        width = constraints.maxWidth;
        return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => x.stop(),
            onHorizontalDragUpdate: (d) =>
                x.value = (x.value + d.delta.dx).clamp(-156, width * .55),
            onHorizontalDragEnd: (d) {
              if (x.value > width * .28) {
                settle(0);
                widget.complete();
              } else if (x.value < -45) {
                HapticFeedback.selectionClick();
                settle(-156);
              } else {
                settle(0);
              }
            },
            child: AnimatedBuilder(
                animation: x,
                builder: (c, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(children: [
                      Positioned.fill(
                          child: ExcludeSemantics(
                              excluding: x.value >= 0,
                              child: Row(children: [
                                Expanded(
                                    child: Container(
                                        color: sage.withValues(alpha: .16),
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.all(20),
                                        child: const Icon(
                                            CupertinoIcons.check_mark,
                                            color: sage))),
                                SizedBox(
                                    width: 78,
                                    child: CupertinoButton(
                                        color: accent,
                                        borderRadius: BorderRadius.zero,
                                        padding: EdgeInsets.zero,
                                        onPressed: () {
                                          settle(0);
                                          widget.schedule();
                                        },
                                        child: const Icon(
                                            CupertinoIcons.calendar,
                                            semanticLabel: 'Schedule task',
                                            color: Colors.white))),
                                SizedBox(
                                    width: 78,
                                    child: CupertinoButton(
                                        color: CupertinoColors.systemRed,
                                        borderRadius: BorderRadius.zero,
                                        padding: EdgeInsets.zero,
                                        onPressed: () {
                                          settle(0);
                                          widget.delete();
                                        },
                                        child: const Icon(CupertinoIcons.trash,
                                            semanticLabel: 'Move task to Trash',
                                            color: Colors.white)))
                              ]))),
                      Transform.translate(
                          offset: Offset(x.value, 0),
                          child:
                              ColoredBox(color: canvas(c), child: widget.child))
                    ]))));
      });
}

/// A small seed unfolds with the pull; avoids an endlessly spinning indicator.
class GritRefreshGlyph extends StatefulWidget {
  const GritRefreshGlyph(
      {super.key,
      required this.progress,
      required this.refreshing,
      this.complete = false});
  final double progress;
  final bool refreshing;
  final bool complete;
  @override
  State<GritRefreshGlyph> createState() => _GritRefreshGlyphState();
}

class _GritRefreshGlyphState extends State<GritRefreshGlyph>
    with SingleTickerProviderStateMixin {
  late final pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    animate();
  }

  @override
  void didUpdateWidget(GritRefreshGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    animate();
  }

  void animate() {
    if (widget.refreshing && !MediaQuery.disableAnimationsOf(context)) {
      if (!pulse.isAnimating) pulse.repeat(reverse: true);
    } else {
      pulse.stop();
      pulse.value = 0;
    }
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AnimatedBuilder(
      animation: pulse,
      builder: (c, _) => SizedBox(
          height: 72,
          child: Center(
              child: Semantics(
                  label: widget.complete
                      ? 'Tasks refreshed'
                      : widget.refreshing
                          ? 'Refreshing tasks'
                          : 'Pull to refresh',
                  child: Transform.scale(
                      scale: .65 +
                          .35 * widget.progress.clamp(0, 1) +
                          .12 * pulse.value,
                      child: Icon(
                          widget.complete
                              ? CupertinoIcons.checkmark_seal
                              : CupertinoIcons.leaf_arrow_circlepath,
                          size: 25,
                          color: accent.withValues(
                              alpha: .35 +
                                  .65 * widget.progress.clamp(0, 1))))))));
}
