import 'dart:async';
import 'package:flutter/material.dart';

/// One transient notice at a time, including with accessible navigation enabled.
class TimedNotice {
  Timer? _timer;
  ScaffoldMessengerState? _messenger;
  int _generation = 0;

  void show(BuildContext context, String message,
      {Duration duration = const Duration(seconds: 5),
      SnackBarAction? action}) {
    dismiss();
    final messenger = ScaffoldMessenger.of(context);
    _messenger = messenger;
    final generation = ++_generation;
    final controller = messenger.showSnackBar(SnackBar(
      content: Text(message),
      duration: duration,
      showCloseIcon: true,
      action: action,
    ));
    // Flutter suppresses its own timeout for accessible notices with an action.
    // Explicit closure also avoids pointer hover keeping feedback indefinitely.
    _timer = Timer(duration, () {
      if (_generation == generation && messenger.mounted) controller.close();
    });
    controller.closed.then((_) {
      if (_generation == generation) {
        _timer?.cancel();
        _timer = null;
      }
    });
  }

  void dismiss() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    final messenger = _messenger;
    if (messenger != null && messenger.mounted) {
      messenger.clearSnackBars();
      messenger.removeCurrentSnackBar();
    }
    _messenger = null;
  }

  void dispose() {
    _generation++;
    _timer?.cancel();
    _messenger = null;
  }
}
