import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'design.dart';
import 'native_ui.dart';

class TaskCompletionMotion extends StatefulWidget {
  const TaskCompletionMotion(
      {super.key, required this.completing, required this.child});
  final bool completing;
  final Widget child;
  @override
  State<TaskCompletionMotion> createState() => _TaskCompletionMotionState();
}

class _TaskCompletionMotionState extends State<TaskCompletionMotion>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController.unbounded(
      vsync: this, value: widget.completing ? 1 : 0);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.stop();
      controller.value = widget.completing ? 1 : 0;
    }
  }

  @override
  void didUpdateWidget(TaskCompletionMotion old) {
    super.didUpdateWidget(old);
    if (old.completing == widget.completing) return;
    final target = widget.completing ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.value = target;
    } else {
      controller.animateWith(SpringSimulation(
          gritSpring, controller.value, target, controller.velocity));
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (context, child) {
        final progress = controller.value.clamp(0.0, 1.0);
        return ClipRect(
            child: Align(
                alignment: Alignment.topCenter,
                heightFactor: 1 - progress,
                child: Opacity(opacity: 1 - progress * .65, child: child)));
      });
}

/// Keeps task actions in reach while the sheet's content scrolls independently.
class TaskDetailShell extends StatelessWidget {
  const TaskDetailShell(
      {super.key,
      required this.child,
      required this.onEdit,
      required this.onClose,
      required this.onComplete,
      required this.onFocus,
      required this.completed});
  final Widget child;
  final VoidCallback onEdit, onClose, onComplete, onFocus;
  final bool completed;
  @override
  Widget build(BuildContext context) {
    if (!compactPlatform(context)) {
      return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 30),
          child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: 720,
                  maxHeight: MediaQuery.sizeOf(context).height * .9),
              child: child));
    }
    final largeText = MediaQuery.textScalerOf(context).scale(17) > 25;
    final complete = FilledButton.icon(
        onPressed: onComplete,
        icon: Icon(
            completed
                ? CupertinoIcons.arrow_uturn_left
                : CupertinoIcons.check_mark,
            size: 18),
        label: Text(completed ? 'Reopen task' : 'Complete task'));
    final focus = OutlinedButton.icon(
        onPressed: onFocus,
        icon: const Icon(CupertinoIcons.play_fill, size: 16),
        label: const Text('Focus'));
    return Scaffold(
        backgroundColor: canvas(context),
        body: SafeArea(
            top: false,
            child: Column(children: [
              Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: ExcludeSemantics(
                      child: Container(
                          width: 36,
                          height: 5,
                          decoration: BoxDecoration(
                              color: secondary(context).withValues(alpha: .35),
                              borderRadius: BorderRadius.circular(4))))),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(children: [
                    IconButton(
                        tooltip: 'Close details',
                        onPressed: onClose,
                        icon: const Icon(CupertinoIcons.xmark_circle_fill,
                            size: 26)),
                    const Expanded(
                        child: Text('Task details',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w600))),
                    IconButton(
                        tooltip: 'Edit task',
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 23)),
                  ])),
              Expanded(child: child),
              Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  decoration: BoxDecoration(
                      color: surface(context),
                      border:
                          Border(top: BorderSide(color: hairline(context)))),
                  child: largeText
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                              complete,
                              const SizedBox(height: 8),
                              focus
                            ])
                      : Row(children: [
                          Expanded(child: complete),
                          const SizedBox(width: 10),
                          focus
                        ])),
            ])));
  }
}

class DetailGroup extends StatelessWidget {
  const DetailGroup({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
          color: surface(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: hairline(context))),
      child: child);
}
