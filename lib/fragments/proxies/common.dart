import 'dart:async';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

Widget currentSelectedProxyNameBuilder({
  required String groupName,
  required Widget Function(String currentGroupName) builder,
}) {
  return Selector2<AppState, Config, String>(
    selector: (_, appState, config) {
      final group = appState.getGroupWithName(groupName);
      final selectedProxyName = config.currentSelectedMap[groupName];
      return group?.getCurrentSelectedName(selectedProxyName ?? "") ?? "";
    },
    builder: (_, currentSelectedProxyName, ___) {
      return builder(currentSelectedProxyName);
    },
  );
}

double get listHeaderHeight {
  final measure = globalState.measure;
  return 20 + measure.titleMediumHeight + 4 + measure.bodyMediumHeight + 2;
}

double getItemHeight(ProxyCardType proxyCardType) {
  final measure = globalState.measure;
  final baseHeight =
      16 + measure.bodyMediumHeight * 2 + measure.bodySmallHeight + 8 + 4;
  return switch (proxyCardType) {
    ProxyCardType.expand => baseHeight + measure.labelSmallHeight + 6,
    ProxyCardType.shrink => baseHeight,
    ProxyCardType.min => baseHeight - measure.bodyMediumHeight,
  };
}

proxyDelayTest(Proxy proxy) async {
  final appController = globalState.appController;
  final proxyName = appController.appState.getRealProxyName(proxy.name);
  globalState.appController.setDelay(
    Delay(
      name: proxyName,
      value: 0,
    ),
  );
  globalState.appController.setDelay(await clashCore.getDelay(proxyName));
}

delayTest(List<Proxy> proxies) async {
  final appController = globalState.appController;
  final proxyNames = proxies
      .map((proxy) => appController.appState.getRealProxyName(proxy.name))
      .toSet()
      .toList();

  final concurrency = appController.config.appSetting.testConcurrency;
  await _runWithConcurrency(proxyNames, concurrency, (proxyName) async {
    appController.setDelay(Delay(name: proxyName, value: 0));
    appController.setDelay(await clashCore.getDelay(proxyName));
  });
  appController.appState.sortNum++;
}

double getScrollToSelectedOffset({
  required String groupName,
  required List<Proxy> proxies,
}) {
  final appController = globalState.appController;
  final columns = other.getProxiesColumns(
    appController.appState.viewWidth,
    appController.config.proxiesStyle.layout,
  );
  final proxyCardType = appController.config.proxiesStyle.cardType;
  final selectedName = appController.getCurrentSelectedName(groupName);
  final findSelectedIndex = proxies.indexWhere(
    (proxy) => proxy.name == selectedName,
  );
  final selectedIndex = findSelectedIndex != -1 ? findSelectedIndex : 0;
  final rows = (selectedIndex / columns).floor();
  return rows * getItemHeight(proxyCardType) + (rows - 1) * 8;
}

proxySpeedTest(Proxy proxy, String groupName) async {
  final appController = globalState.appController;
  final proxyName = appController.appState.getRealProxyName(proxy.name);
  appController.appState.showSpeed = true;

  // 先测延迟，延迟通过才测速度
  appController.setDelay(Delay(name: proxyName, value: 0));
  final delay = await clashCore.getDelay(proxyName);
  appController.setDelay(delay);

  if (delay.value != null && delay.value! > 0) {
    appController.appState.setSpeed(proxyName, -1);
    final speedResult = await clashCore.getSpeed(
      proxyName,
      appController.config.appSetting.speedTestUrl,
      10000,
    );
    appController.appState.setSpeed(proxyName, speedResult.speed);
  } else {
    appController.appState.setSpeed(proxyName, null);
  }
  appController.appState.sortNum++;
}

speedTest(List<Proxy> proxies, String groupName) async {
  final appController = globalState.appController;
  final proxyNames = proxies
      .map((proxy) => appController.appState.getRealProxyName(proxy.name))
      .toSet()
      .toList();

  appController.appState.showSpeed = true;
  final concurrency = appController.config.appSetting.testConcurrency;
  final speedTestUrl = appController.config.appSetting.speedTestUrl;

  // 每个代理独立执行：先测延迟 → 延迟通过再测速度
  // getSpeed 使用 proxy.DialContext 直接建连，不需要 changeProxy，可安全并发
  await _runWithConcurrency(proxyNames, concurrency, (proxyName) async {
    // Step 1: 测延迟
    appController.setDelay(Delay(name: proxyName, value: 0));
    final delay = await clashCore.getDelay(proxyName);
    appController.setDelay(delay);

    // Step 2: 延迟通过才测速度
    if (delay.value != null && delay.value! > 0) {
      appController.appState.setSpeed(proxyName, -1);
      final speedResult =
          await clashCore.getSpeed(proxyName, speedTestUrl, 10000);
      appController.appState.setSpeed(proxyName, speedResult.speed);
    } else {
      appController.appState.setSpeed(proxyName, null);
    }
  });

  appController.appState.sortNum++;
}

/// Run tasks with limited concurrency.
/// Unlike batching pre-created Futures, this actually limits concurrency
/// by only starting new tasks when a slot is available.
Future<void> _runWithConcurrency<T>(
  List<T> items,
  int concurrency,
  Future<void> Function(T item) task,
) async {
  var running = 0;
  final completer = Completer<void>();
  var remaining = items.length;
  var index = 0;

  if (items.isEmpty) {
    return;
  }

  void startNext() {
    while (running < concurrency && index < items.length) {
      final item = items[index];
      index++;
      running++;
      task(item).whenComplete(() {
        running--;
        remaining--;
        if (remaining == 0) {
          completer.complete();
        } else {
          startNext();
        }
      });
    }
  }

  startNext();
  await completer.future;
}
