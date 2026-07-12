import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

final networkDetectionState = ValueNotifier<NetworkDetectionState>(
  const NetworkDetectionState(
    isTesting: true,
    ipInfo: null,
  ),
);

class NetworkDetection extends StatefulWidget {
  const NetworkDetection({super.key});

  @override
  State<NetworkDetection> createState() => _NetworkDetectionState();
}

class _NetworkDetectionState extends State<NetworkDetection> {
  bool? _preIsStart;
  Function? _checkIpDebounce;
  Timer? _setTimeoutTimer;
  Timer? _ipCheckTimeoutTimer;
  CancelToken? cancelToken;

  _checkIp() async {
    if (isLowMemoryMode) return;
    if (isReducedMemoryMode) {
      final appFlowingState = globalState.appController.appFlowingState;
      if (!appFlowingState.isStart) return;
    }
    final appState = globalState.appController.appState;
    final appFlowingState = globalState.appController.appFlowingState;
    final isInit = appState.isInit;
    if (!isInit) return;
    final isStart = appFlowingState.isStart;
    if (_preIsStart == false && _preIsStart == isStart) return;
    _clearSetTimeoutTimer();
    _clearIpCheckTimeoutTimer();
    networkDetectionState.value = networkDetectionState.value.copyWith(
      isTesting: true,
      ipInfo: null,
    );
    _preIsStart = isStart;
    if (cancelToken != null) {
      cancelToken!.cancel();
      cancelToken = null;
    }
    cancelToken = CancelToken();

    // 启动IP检查整体超时计时器，超时后自动取消请求并显示超时提示
    _ipCheckTimeoutTimer = Timer(ipCheckTimeout, () {
      if (cancelToken != null) {
        cancelToken!.cancel();
        cancelToken = null;
      }
      networkDetectionState.value = networkDetectionState.value.copyWith(
        isTesting: false,
        ipInfo: null,
      );
    });

    try {
      final ipInfo = await request.checkIp(cancelToken: cancelToken);
      // 请求完成，清除超时计时器
      _clearIpCheckTimeoutTimer();
      if (ipInfo != null) {
        networkDetectionState.value = networkDetectionState.value.copyWith(
          isTesting: false,
          ipInfo: ipInfo,
        );
        return;
      }
      _clearSetTimeoutTimer();
      _setTimeoutTimer = Timer(const Duration(milliseconds: 300), () {
        networkDetectionState.value = networkDetectionState.value.copyWith(
          isTesting: false,
          ipInfo: null,
        );
      });
    } catch (e) {
      // 请求异常，清除超时计时器
      _clearIpCheckTimeoutTimer();
      if (e.toString() == "cancelled") {
        // 超时取消或手动取消时，保持当前状态（超时计时器已设置isTesting=false）
        // 仅在尚未被超时处理覆盖时更新状态
        if (networkDetectionState.value.isTesting) {
          networkDetectionState.value = networkDetectionState.value.copyWith(
            isTesting: true,
            ipInfo: null,
          );
        }
      }
    }
  }

  _clearSetTimeoutTimer() {
    if (_setTimeoutTimer != null) {
      _setTimeoutTimer?.cancel();
      _setTimeoutTimer = null;
    }
  }

  /// 清除IP检查超时计时器
  _clearIpCheckTimeoutTimer() {
    if (_ipCheckTimeoutTimer != null) {
      _ipCheckTimeoutTimer?.cancel();
      _ipCheckTimeoutTimer = null;
    }
  }

  _checkIpContainer(Widget child) {
    return Selector<AppState, num>(
      selector: (_, appState) {
        return appState.checkIpNum;
      },
      builder: (_, checkIpNum, child) {
        if (_checkIpDebounce != null) {
          _checkIpDebounce!();
        }
        return child!;
      },
      child: child,
    );
  }

  @override
  dispose() {
    _clearIpCheckTimeoutTimer();
    super.dispose();
  }

  String countryCodeToEmoji(String countryCode) {
    final String code = countryCode.toUpperCase();
    if (code.length != 2) {
      return countryCode;
    }
    final int firstLetter = code.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final int secondLetter = code.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCode(firstLetter) + String.fromCharCode(secondLetter);
  }

  @override
  Widget build(BuildContext context) {
    _checkIpDebounce ??= debounce(_checkIp);
    return _checkIpContainer(
      ValueListenableBuilder<NetworkDetectionState>(
        valueListenable: networkDetectionState,
        builder: (_, state, __) {
          final ipInfo = state.ipInfo;
          final isTesting = state.isTesting;
          return CommonCard(
            onPressed: () {},
            child: Column(
              children: [
                Flexible(
                  flex: 0,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.network_check,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        Flexible(
                          flex: 1,
                          child: FadeBox(
                            child: isTesting
                                ? Text(
                                    appLocalizations.checking,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  )
                                : ipInfo != null
                                    ? Container(
                                        alignment: Alignment.centerLeft,
                                        height: globalState
                                            .measure.titleMediumHeight,
                                        child: Text(
                                          countryCodeToEmoji(
                                              ipInfo.countryCode),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
                                                fontFamily:
                                                    FontFamily.twEmoji.value,
                                              ),
                                        ),
                                      )
                                    : Text(
                                        appLocalizations.checkError,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  height: globalState.measure.titleLargeHeight + 24 - 2,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.all(16).copyWith(top: 0),
                  child: FadeBox(
                    child: ipInfo != null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                flex: 1,
                                child: TooltipText(
                                  text: Text(
                                    ipInfo.ip,
                                    style: context.textTheme.titleLarge
                                        ?.toSoftBold.toMinus,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : FadeBox(
                            child: isTesting == false && ipInfo == null
                                ? Text(
                                    appLocalizations.checkIpTimeout,
                                    style: context.textTheme.titleLarge
                                        ?.copyWith(color: Colors.red)
                                        .toSoftBold
                                        .toMinus,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : Container(
                                    padding: const EdgeInsets.all(2),
                                    child: const AspectRatio(
                                      aspectRatio: 1,
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                          ),
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }
}
