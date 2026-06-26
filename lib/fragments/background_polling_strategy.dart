import 'package:fl_clash/common/low_memory_mode.dart';

enum PollingMode {
  stopped,
  normal,
  reduced,
}

PollingMode resolvePollingMode({
  required bool isVisible,
  required bool isInBackground,
  required LowMemoryMode lowMemoryMode,
}) {
  if (!isVisible || isInBackground || lowMemoryMode == LowMemoryMode.low) {
    return PollingMode.stopped;
  }

  if (lowMemoryMode == LowMemoryMode.reduced) {
    return PollingMode.reduced;
  }

  return PollingMode.normal;
}
