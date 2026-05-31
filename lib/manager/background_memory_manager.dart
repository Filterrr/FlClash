import 'dart:io';

import 'package:fl_clash/common/low_memory_mode.dart';
import 'package:fl_clash/common/resource_controller.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';

class BackgroundMemoryManager {
  static final BackgroundMemoryManager _instance =
      BackgroundMemoryManager._internal();
  factory BackgroundMemoryManager() => _instance;
  BackgroundMemoryManager._internal();

  bool _isInitialized = false;

  void init() {
    if (_isInitialized) return;
    _isInitialized = true;
    resourceController.init();
  }

  void onAppPaused() {
    enterLowMemoryMode();
    _reduceGlobalStateTimerFrequency();
    _requestGc();
  }

  void onAppResumed() {
    exitLowMemoryMode();
    _restoreGlobalStateTimerFrequency();
  }

  void onWindowHidden() {
    enterLowMemoryMode();
    _reduceGlobalStateTimerFrequency();
    _requestGc();
  }

  void onWindowShown() {
    exitLowMemoryMode();
    _restoreGlobalStateTimerFrequency();
  }

  void _reduceGlobalStateTimerFrequency() {
    globalState.stopListenUpdate();
  }

  void _restoreGlobalStateTimerFrequency() {
    if (globalState.isStart) {
      globalState.startListenUpdate();
    }
  }

  void _requestGc() {
    clashCore.requestGc();
  }

  void dispose() {
    resourceController.dispose();
    _isInitialized = false;
  }
}

final backgroundMemoryManager = BackgroundMemoryManager();
