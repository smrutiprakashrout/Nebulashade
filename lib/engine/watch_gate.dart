import 'package:nebulashade/constants/colours.dart';

abstract interface class WatchGateHandle {
  void suspend();
  Future<void> resume({Future<void> Function()? reinit});
}

class WatchGate implements WatchGateHandle {
  static int _holds = 0;
  static bool get suspended => _holds > 0;

  @override
  void suspend() => _holds++;

  @override
  Future<void> resume({Future<void> Function()? reinit}) async {
    if (_holds == 0) return;
    _holds--;
    if (_holds != 0) return;
    try {
      if (reinit != null) {
        await reinit();
      } else {
        AppColors.init();
      }
    } catch (_) {}
  }
}
