import 'dart:async';

enum LowMemoryMode {
  normal,
  low,
}

final ValueNotifier<LowMemoryMode> lowMemoryModeNotifier =
    ValueNotifier<LowMemoryMode>(LowMemoryMode.normal);

bool get isLowMemoryMode =>
    lowMemoryModeNotifier.value == LowMemoryMode.low;

void enterLowMemoryMode() {
  if (lowMemoryModeNotifier.value == LowMemoryMode.low) return;
  lowMemoryModeNotifier.value = LowMemoryMode.low;
}

void exitLowMemoryMode() {
  if (lowMemoryModeNotifier.value == LowMemoryMode.normal) return;
  lowMemoryModeNotifier.value = LowMemoryMode.normal;
}
