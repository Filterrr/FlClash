import 'dart:io';

import 'package:fl_clash/clash/clash.dart';
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

void _updateTrafficPush() {
  final shouldPause = isLowMemoryMode || isReducedMemoryMode;
  if (Platform.isAndroid) {
    if (shouldPause) {
      clashLib?.pauseTrafficPush();
    } else {
      clashLib?.resumeTrafficPush();
    }
  } else {
    if (shouldPause) {
      clashService?.pauseTrafficPush();
    } else {
      clashService?.resumeTrafficPush();
    }
  }
}

void enterLowMemoryMode() {
  if (lowMemoryModeNotifier.value == LowMemoryMode.low) return;
  lowMemoryModeNotifier.value = LowMemoryMode.low;
  _updateTrafficPush();
}

void enterReducedMemoryMode() {
  if (lowMemoryModeNotifier.value == LowMemoryMode.reduced) return;
  if (lowMemoryModeNotifier.value == LowMemoryMode.low) return;
  lowMemoryModeNotifier.value = LowMemoryMode.reduced;
  _updateTrafficPush();
}

void exitLowMemoryMode() {
  if (lowMemoryModeNotifier.value == LowMemoryMode.normal) return;
  lowMemoryModeNotifier.value = LowMemoryMode.normal;
  _updateTrafficPush();
}
