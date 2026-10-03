import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Mouse/stylus drags begin immediately. Touch waits so the page can still scroll.
class ScheduleTaskDrag<T extends Object> extends StatefulWidget {
  const ScheduleTaskDrag(
      {super.key,
      required this.data,
      required this.child,
      required this.feedback,
      this.onStart,
      this.onEnd});
  final T data;
  final Widget child, feedback;
  final VoidCallback? onStart, onEnd;
  @override
  State<ScheduleTaskDrag<T>> createState() => _ScheduleTaskDragState<T>();
}

class _ScheduleTaskDragState<T extends Object>
    extends State<ScheduleTaskDrag<T>> {
  Timer? edgeScroll;
  Offset? pointer;
  void start() {
    widget.onStart?.call();
    edgeScroll?.cancel();
    edgeScroll = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || pointer == null) return;
      final scrollable = Scrollable.maybeOf(context);
      final render = scrollable?.context.findRenderObject();
      if (scrollable == null || render is! RenderBox || !render.hasSize) return;
      final top = render.localToGlobal(Offset.zero).dy;
      final bottom = top + render.size.height;
      final dy = pointer!.dy;
      final direction = dy < top + 80
          ? -1
          : dy > bottom - 80
              ? 1
              : 0;
      if (direction == 0) return;
      final position = scrollable.position;
      final next = (position.pixels + direction * 10)
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if (next != position.pixels) position.jumpTo(next);
    });
  }

  void end(DraggableDetails _) {
    edgeScroll?.cancel();
    pointer = null;
    widget.onEnd?.call();
  }

  @override
  void dispose() {
    edgeScroll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _MouseDrag<T>(
      data: widget.data,
      feedback: widget.feedback,
      onDragStarted: start,
      onDragEnd: end,
      onDragUpdate: (details) => pointer = details.globalPosition,
      childWhenDragging: Opacity(opacity: .35, child: widget.child),
      child: _TouchDrag<T>(
          data: widget.data,
          feedback: widget.feedback,
          onDragStarted: start,
          onDragEnd: end,
          onDragUpdate: (details) => pointer = details.globalPosition,
          childWhenDragging: Opacity(opacity: .35, child: widget.child),
          child: widget.child));
}

class _MouseDrag<T extends Object> extends Draggable<T> {
  const _MouseDrag(
      {required super.data,
      required super.child,
      required super.feedback,
      required super.childWhenDragging,
      required super.onDragStarted,
      required super.onDragEnd,
      required super.onDragUpdate})
      : super(maxSimultaneousDrags: 1);
  @override
  MultiDragGestureRecognizer createRecognizer(
          GestureMultiDragStartCallback onStart) =>
      ImmediateMultiDragGestureRecognizer(supportedDevices: const {
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      }, allowedButtonsFilter: allowedButtonsFilter)
        ..onStart = onStart;
}

class _TouchDrag<T extends Object> extends Draggable<T> {
  const _TouchDrag(
      {required super.data,
      required super.child,
      required super.feedback,
      required super.childWhenDragging,
      required super.onDragStarted,
      required super.onDragEnd,
      required super.onDragUpdate})
      : super(maxSimultaneousDrags: 1);
  @override
  MultiDragGestureRecognizer createRecognizer(
          GestureMultiDragStartCallback onStart) =>
      DelayedMultiDragGestureRecognizer(
          delay: const Duration(milliseconds: 300),
          supportedDevices: const {
            PointerDeviceKind.touch,
            PointerDeviceKind.unknown
          },
          allowedButtonsFilter: allowedButtonsFilter)
        ..onStart = onStart;
}
