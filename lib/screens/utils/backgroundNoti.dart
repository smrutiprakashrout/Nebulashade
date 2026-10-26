import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:nebulashade/constants/colours.dart'; // Import your AppColors file
import 'package:nebulashade/engine/watch_gate.dart';

bool shouldReinitializeAppColorsForEvent(
    FileSystemEvent event, String targetPath) {
  if (event.path != targetPath ||
      (event is! FileSystemModifyEvent && event is! FileSystemCreateEvent)) {
    return false;
  }
  if (WatchGate.suspended) return false;
  return true;
}

class AppColorsNotifier extends ValueNotifier<Color> {
  AppColorsNotifier(Color value) : super(value);

  late File _file;
  StreamSubscription<FileSystemEvent>? _watcher;

  void startWatching() {
    final home = Platform.environment['HOME'];
    if (home == null) {
      print("HOME environment variable not found.");
      return;
    }

    _file = File('$home/.config/gtk-4.0/gtk.css');

    if (!_file.existsSync()) {
      print("GTK theme file not found.");
      return;
    }

    _watcher = _file.parent.watch().listen((event) {
      if (!shouldReinitializeAppColorsForEvent(event, _file.path)) return;
      AppColors.init();
      value = AppColors.background;
    });
  }

  @override
  void dispose() {
    _watcher?.cancel();
    super.dispose();
  }
}
