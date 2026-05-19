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
  CancelToken? cancelToken;

  _checkIp() async {
    final appState = globalState.appController.appState;
    final appFlowingState = globalState.appController.appFlowingState;
    final isInit = appState.isInit;
    if (!isInit) return;
    final isStart = appFlowingState.isStart;
    if (_preIsStart == false && _preIsStart == isStart) return;
    _clearSetTimeoutTimer();
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
    try {
      final ipInfo = await request.checkIp(cancelToken: cancelToken);
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
      if (e.toString() == "cancelled") {
        networkDetectionState.value = networkDetectionState.value.copyWith(
          isTesting: true,
          ipInfo: null,
        );
      }
    }
  }

  _clearSetTimeoutTimer() {
    if (_setTimeoutTimer != null) {
      _setTimeoutTimer?.cancel();
      _setTimeoutTimer = null;
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
          final emojiTextStyle =
              context.textTheme.titleMedium?.toLight.copyWith(
            fontFamily: FontFamily.twEmoji.value,
          );
          final titleTextStyle = context.colorScheme.onSurfaceVariant;
          final descTextStyle = context.textTheme.titleSmall?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          );
          return CommonCard(
            onPressed: () {},
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  height: globalState.measure.titleMediumHeight + 16,
                  padding: baseInfoEdgeInsets.copyWith(bottom: 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      ipInfo != null
                          ? Text(
                              countryCodeToEmoji(ipInfo.countryCode),
                              style: emojiTextStyle,
                            )
                          : Icon(Icons.network_check, color: titleTextStyle),
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 1,
                        child: TooltipText(
                          text: Text(
                            appLocalizations.networkDetection,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: descTextStyle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      AspectRatio(
                        aspectRatio: 1,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            globalState.showMessage(
                              title: appLocalizations.tip,
                              message: TextSpan(
                                text: appLocalizations.detectionTip,
                              ),
                              onTab: () {
                                Navigator.of(context).pop();
                              },
                            );
                          },
                          icon: Icon(
                            size: 16,
                            Icons.info_outline,
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: baseInfoEdgeInsets.copyWith(top: 0),
                  child: SizedBox(
                    height: globalState.measure.bodyMediumHeight + 2,
                    child: FadeThroughBox(
                      child: ipInfo != null
                          ? TooltipText(
                              text: Text(
                                ipInfo.ip,
                                style: context.textTheme.bodyMedium?.toLight,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          : isTesting == false && ipInfo == null
                              ? Text(
                                  'timeout',
                                  style: context.textTheme.bodyMedium?.copyWith(
                                      color: Colors.red),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : Container(
                                  padding: const EdgeInsets.all(2),
                                  child: const AspectRatio(
                                    aspectRatio: 1,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 3),
                                  ),
                                ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
