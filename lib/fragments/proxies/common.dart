import 'dart:async';
import 'dart:io';

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
    final speed = await _testProxySpeed(proxyName, groupName);
    appController.appState.setSpeed(proxyName, speed);
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

  // Step 1: 并发测延迟（getDelay 直接走 core URLTest，不涉及 changeProxy，可安全并发）
  await _runWithConcurrency(proxyNames, concurrency, (proxyName) async {
    appController.setDelay(Delay(name: proxyName, value: 0));
    final delay = await clashCore.getDelay(proxyName);
    appController.setDelay(delay);
  });

  // Step 2: 逐个测速度（changeProxy 影响整个组，必须串行，确保 a 流量走 a、b 流量走 b）
  for (final proxyName in proxyNames) {
    final delay = appController.appState.getDelay(proxyName);
    if (delay != null && delay > 0) {
      appController.appState.setSpeed(proxyName, -1);
      final speed = await _testProxySpeed(proxyName, groupName);
      appController.appState.setSpeed(proxyName, speed);
    } else {
      appController.appState.setSpeed(proxyName, null);
    }
  }

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

Future<double?> _testProxySpeed(String proxyName, String groupName) async {
  final appController = globalState.appController;
  final speedTestUrl = appController.config.appSetting.speedTestUrl;
  final mixedPort = appController.clashConfig.mixedPort;
  final originalProxyName = appController.getCurrentSelectedName(groupName);

  final client = HttpClient();
  client.findProxy = (uri) => 'PROXY 127.0.0.1:$mixedPort';
  client.connectionTimeout = const Duration(seconds: 10);

  try {
    await clashCore.changeProxy(ChangeProxyParams(
      groupName: groupName,
      proxyName: proxyName,
    ));

    final stopwatch = Stopwatch()..start();
    final request = await client.getUrl(Uri.parse(speedTestUrl));
    final response = await request.close();

    int totalBytes = 0;
    double maxSpeed = 0;

    await for (final chunk in response) {
      totalBytes += chunk.length;
      final elapsedSeconds = stopwatch.elapsedMilliseconds / 1000;
      if (elapsedSeconds > 0) {
        final currentSpeed = totalBytes / elapsedSeconds;
        if (currentSpeed > maxSpeed) {
          maxSpeed = currentSpeed;
        }
      }
    }

    stopwatch.stop();

    return maxSpeed > 0 ? maxSpeed : null;
  } catch (e) {
    return null;
  } finally {
    client.close();
    if (originalProxyName.isNotEmpty) {
      await clashCore.changeProxy(ChangeProxyParams(
        groupName: groupName,
        proxyName: originalProxyName,
      ));
    }
  }
}
