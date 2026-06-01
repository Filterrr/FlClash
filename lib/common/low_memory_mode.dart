import 'package:flutter/foundation.dart';

enum LowMemoryMode {
  normal,
  reduced,
  low,
}

final ValueNotifier<LowMemoryMode> lowMemoryModeNotifier =
    ValueNotifier<LowMemoryMode>(LowMemoryMode.normal);

bool get isLowMemoryMode =>
    lowMemoryModeNotifier.value == LowMemoryMode.low;

bool get isReducedMemoryMode =>
    lowMemoryModeNotifier.value == LowMemoryMode.reduced;

bool get isNormalMemoryMode =>
    lowMemoryModeNotifier.value == LowMemoryMode.normal;

int get lowMemoryModeIndex => lowMemoryModeNotifier.value.index;

void enterLowMemoryMode() {
  if (lowMemoryModeNotifier.value == LowMemoryMode.low) return;
  lowMemoryModeNotifier.value = LowMemoryMode.low;
}

void enterReducedMemoryMode() {
  if (lowMemoryModeNotifier.value == LowMemoryMode.reduced) return;
  if (lowMemoryModeNotifier.value == LowMemoryMode.low) return;
  lowMemoryModeNotifier.value = LowMemoryMode.reduced;
}

void exitLowMemoryMode() {
  if (lowMemoryModeNotifier.value == LowMemoryMode.normal) return;
  lowMemoryModeNotifier.value = LowMemoryMode.normal;
}
