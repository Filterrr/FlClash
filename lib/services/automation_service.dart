import 'dart:async';
import 'dart:io';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/services/node_metrics.dart';
import 'package:fl_clash/state.dart';

/// 自动化配置:定时测速 / 优选 / 网络变化触发。
///
/// 手写模型,存储就是它自己的 toJson。
class AutomationConfig {
  /// 定时测速总开关。
  bool autoTestEnabled;

  /// 测速间隔(分钟)。
  int intervalMinutes;

  /// 目标策略组名。为空表示「所有可选中的组」。
  String? groupName;

  /// 测完是否自动切到最快节点。
  bool autoSwitch;

  /// 连续多少次测速都是同一个节点最快才真正切换。
  ///
  /// 这个值存在的意义:单次测速的抖动很大,立刻切换会让节点在
  /// 几个候选之间反复横跳,体验比不动更糟。
  int switchStreak;

  /// 网络类型变化(WiFi <-> 蜂窝)时立刻触发一次测速优选。
  bool triggerOnNetworkChange;

  AutomationConfig({
    this.autoTestEnabled = false,
    this.intervalMinutes = 10,
    this.groupName,
    this.autoSwitch = false,
    this.switchStreak = 2,
    this.triggerOnNetworkChange = false,
  });

  factory AutomationConfig.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v, int fallback) {
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? fallback;
    }

    return AutomationConfig(
      autoTestEnabled: json['autoTestEnabled'] == true,
      intervalMinutes: asInt(json['intervalMinutes'], 10),
      groupName: json['groupName']?.toString(),
      autoSwitch: json['autoSwitch'] == true,
      switchStreak: asInt(json['switchStreak'], 2),
      triggerOnNetworkChange: json['triggerOnNetworkChange'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'autoTestEnabled': autoTestEnabled,
        'intervalMinutes': intervalMinutes,
        'groupName': groupName,
        'autoSwitch': autoSwitch,
        'switchStreak': switchStreak,
        'triggerOnNetworkChange': triggerOnNetworkChange,
      };
}

/// 自动测速 / 优选 / 网络变化自动化。
///
/// 定时器只在 App 前台有意义 —— Flutter 的 Timer 在后台会被系统挂起,
/// 这一点不假装能绕过。真正的常驻自动化应该下沉到原生侧,那是另一个量级
/// 的改动,不在这一版范围内。
class AutomationService {
  static const String _storeName = 'automation.json';

  /// 网络类型轮询间隔。用轮询而不是广播,是因为 dart:io 层面拿不到
  /// Android 的网络变化回调;60s 的代价可以接受,而且只在功能开启时才跑。
  static const Duration _networkPollInterval = Duration(seconds: 60);

  AutomationConfig config = AutomationConfig();

  Timer? _testTimer;
  Timer? _networkTimer;
  bool _running = false;
  bool _loaded = false;
  String? _lastNetworkKind;

  /// 连续最快节点的追踪(节点名 -> 连续次数)
  String? _streakNode;
  int _streakCount = 0;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final raw = await LocalStore.read(_storeName);
    if (raw is Map) {
      config = AutomationConfig.fromJson(Map<String, dynamic>.from(raw));
    }
  }

  Future<void> save() async {
    await LocalStore.write(_storeName, config.toJson());
  }

  /// 应用配置:重建定时器。
  Future<void> apply() async {
    await load();
    await save();
    stop();
    if (config.autoTestEnabled) {
      final interval = Duration(
        minutes: config.intervalMinutes.clamp(1, 24 * 60),
      );
      _testTimer = Timer.periodic(interval, (_) => testOnce());
    }
    if (config.triggerOnNetworkChange) {
      _networkTimer = Timer.periodic(_networkPollInterval, (_) => _pollNetwork());
      unawaited(_pollNetwork(initial: true));
    }
  }

  void stop() {
    _testTimer?.cancel();
    _testTimer = null;
    _networkTimer?.cancel();
    _networkTimer = null;
  }

  /// 当前网络类型:WiFi / 其它。
  ///
  /// 只区分这两类 —— 精确到 SSID 在 Android 10+ 需要定位权限且后台受限,
  /// 那个代价和收益不成比例。
  static Future<String> currentNetworkKind() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      final hasWifi = interfaces.any(
        (e) => e.isWifi && e.addresses.isNotEmpty,
      );
      return hasWifi ? 'wifi' : 'cellular';
    } catch (_) {
      return 'unknown';
    }
  }

  Future<void> _pollNetwork({bool initial = false}) async {
    final kind = await currentNetworkKind();
    if (initial || _lastNetworkKind == null) {
      _lastNetworkKind = kind;
      return;
    }
    if (kind == _lastNetworkKind) return;
    _lastNetworkKind = kind;
    // 网络换了,历史延迟基本作废 —— 立刻重测一轮
    await testOnce();
  }

  /// 执行一轮测速(可选自动切换)。可被 UI 手动调用。
  Future<List<Delay>> testOnce() async {
    if (_running) return const [];
    _running = true;
    try {
      final groups = await _resolveGroups();
      if (groups.isEmpty) return const [];
      final concurrency =
          globalState.appController.config.appSetting.testConcurrency
              .clamp(1, 20);
      final delays = <Delay>[];
      for (final group in groups) {
        final names = group.all
            .map((e) => e.name)
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();
        if (names.isEmpty) continue;
        await _runWithConcurrency(names, concurrency, (name) async {
          try {
            final delay = await clashCore.getDelay(name);
            delays.add(delay);
            // 走 AppController 是为了顺带刷新 UI 上的延迟显示;
            // 节点质量采样已经在 setDelay 里收口,这里不能重复记。
            globalState.appController.setDelay(delay);
          } catch (_) {
            // 单个节点测不通不该中断整轮
          }
        });
        if (config.autoSwitch) {
          await _maybeSwitch(group, names);
        }
      }
      globalState.appController.appState.sortNum++;
      return delays;
    } catch (_) {
      return const [];
    } finally {
      _running = false;
    }
  }

  Future<List<Group>> _resolveGroups() async {
    final proxies = await clashCore.getProxiesGroups();
    final candidates = proxies
        .where((e) => e.hidden != true && e.all.isNotEmpty)
        .toList();
    final target = config.groupName;
    if (target == null || target.isEmpty) {
      // 没指定就只盯「可选中的组」,别去动 URLTest 这类自动组
      return candidates.where((e) => e.type == GroupType.Selector).toList();
    }
    return candidates.where((e) => e.name == target).toList();
  }

  Future<void> _maybeSwitch(Group group, List<String> names) async {
    String? best;
    int? bestDelay;
    for (final name in names) {
      final delay = nodeMetrics.latestDelay(name);
      if (delay == null || delay <= 0) continue;
      if (bestDelay == null || delay < bestDelay) {
        bestDelay = delay;
        best = name;
      }
    }
    if (best == null || bestDelay == null) return;

    if (best == _streakNode) {
      _streakCount++;
    } else {
      _streakNode = best;
      _streakCount = 1;
    }
    if (_streakCount < config.switchStreak.clamp(1, 10)) return;

    final current = group.now;
    if (current == best) return;
    try {
      await clashCore.changeProxy(
        ChangeProxyParams(groupName: group.name, proxyName: best),
      );
    } catch (_) {
      return;
    }
  }

  static Future<void> _runWithConcurrency(
    List<String> items,
    int limit,
    Future<void> Function(String) task,
  ) async {
    final queue = [...items];
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final item = queue.removeAt(0);
        await task(item);
      }
    }

    final workers = <Future<void>>[];
    for (var i = 0; i < limit && queue.isNotEmpty; i++) {
      workers.add(worker());
    }
    await Future.wait(workers);
  }
}

final automationService = AutomationService();
