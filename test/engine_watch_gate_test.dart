import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebulashade/engine/watch_gate.dart';
import 'package:nebulashade/screens/utils/backgroundNoti.dart';

void main() {
  test('nested suspend/resume reinitializes once at zero', () async {
    final gate = WatchGate();
    var calls = 0;
    gate.suspend();
    gate.suspend();
    expect(WatchGate.suspended, isTrue);
    await gate.resume(reinit: () async => calls++);
    expect(calls, 0);
    expect(WatchGate.suspended, isTrue);
    await gate.resume(reinit: () async => calls++);
    expect(calls, 1);
    expect(WatchGate.suspended, isFalse);
  });

  test('resume without suspend is a no-op', () async {
    var calls = 0;
    await WatchGate().resume(reinit: () async => calls++);
    expect(calls, 0);
  });

  test('watcher event seam ignores events while suspended', () async {
    const filePath = '/temp/gtk.css';
    final event = FileSystemModifyEvent(filePath, false, true);
    expect(shouldReinitializeAppColorsForEvent(event, filePath), isTrue);
    final gate = WatchGate()..suspend();
    expect(shouldReinitializeAppColorsForEvent(event, filePath), isFalse);
    await gate.resume(reinit: () async {});
    expect(shouldReinitializeAppColorsForEvent(event, filePath), isTrue);
  });
}
