import 'dart:async';
import 'dart:math';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';

/// 节点延迟采样与质量统计。
///
/// 挂钩点是 `AppController.setDelay` —— 手动测速、批量测速、定时测速
/// 最终都会走那里,一处收口,不用在四个测速函数里各记一遍。
///
/// 保留策略:每个节点最近 [_maxPerNode] 次采样,落盘节流 [_persistInterval]。
/// 延迟数据的时效性很强,留太久只会变成噪声。
class NodeMetrics {
  static const String _storeName = 'node_metrics.json';
  static const int _maxPerNode = 80;
  static const Duration _persistInterval = Duration(seconds: 60);

  final Map<String, List<DelaySample>> _samples = {};
  bool _loaded = false;
  DateTime? _lastPersist;

  /// 在 App 启动早期调用一次,避免第一次 record 时把历史覆盖掉。
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final raw = await LocalStore.read(_storeName);
    if (raw is! Map) return;
    raw.forEach((key, value) {
      if (key is! String || value is! List) return;
      final list = <DelaySample>[];
      for (final item in value) {
        if (item is Map) {
          list.add(DelaySample.fromJson(Map<String, dynamic>.from(item)));
        }
      }
      if (list.isNotEmpty) _samples[key] = list;
    });
  }

  /// 记录一次测速结果。同步、廉价,可以直接挂在高频路径上。
  void record(Delay delay) {
    final name = delay.name;
    if (name.isEmpty || !_loaded) return;
    final value = delay.value;
    final list = _samples.putIfAbsent(name, () => <DelaySample>[]);
    list.add(
      DelaySample(
        time: DateTime.now().millisecondsSinceEpoch,
        // 0 和负数都是「失败」的约定表示,统一收敛成 null
        delay: (value == null || value <= 0) ? null : value,
      ),
    );
    if (list.length > _maxPerNode) {
      list.removeRange(0, list.length - _maxPerNode);
    }
    _maybePersist();
  }

  List<DelaySample> samplesOf(String name) =>
      List.unmodifiable(_samples[name] ?? const <DelaySample>[]);

  /// 最近一次成功延迟;没有成功记录返回 null。
  int? latestDelay(String name) {
    final list = _samples[name];
    if (list == null) return null;
    for (var i = list.length - 1; i >= 0; i--) {
      if (list[i].isSuccess) return list[i].delay;
    }
    return null;
  }

  /// 最近 N 次采样的成功率。样本不足时返回 null。
  double? successRate(String name, {int window = 10}) {
    final list = _samples[name];
    if (list == null || list.isEmpty) return null;
    final slice = list.length <= window
        ? list
        : list.sublist(list.length - window);
    final success = slice.where((e) => e.isSuccess).length;
    return success / slice.length;
  }

  /// 最近 N 次成功采样的平均延迟。
  int? averageDelay(String name, {int window = 10}) {
    final list = _samples[name];
    if (list == null) return null;
    final values = <int>[];
    for (var i = list.length - 1; i >= 0 && values.length < window; i--) {
      final value = list[i].delay;
      if (value != null && value > 0) values.add(value);
    }
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) ~/ values.length;
  }

  /// 抖动:最近 N 次成功采样的标准差。数值越小越稳。
  int? jitter(String name, {int window = 10}) {
    final list = _samples[name];
    if (list == null) return null;
    final values = <int>[];
    for (var i = list.length - 1; i >= 0 && values.length < window; i--) {
      final value = list[i].delay;
      if (value != null && value > 0) values.add(value);
    }
    if (values.length < 2) return null;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values
            .map((e) => (e - mean) * (e - mean))
            .reduce((a, b) => a + b) /
        values.length;
    return sqrt(variance).round();
  }

  /// 所有有记录的节点名,按最近延迟升序(没测通的排最后)。
  List<String> orderedNames() {
    final names = _samples.keys.toList();
    names.sort((a, b) {
      final la = latestDelay(a) ?? 1 << 30;
      final lb = latestDelay(b) ?? 1 << 30;
      return la.compareTo(lb);
    });
    return names;
  }

  Map<String, dynamic> snapshot() => {
        for (final entry in _samples.entries)
          entry.key: entry.value.map((e) => e.toJson()).toList(),
      };

  Future<void> clear() async {
    _samples.clear();
    await LocalStore.write(_storeName, const <String, dynamic>{});
  }

  void _maybePersist() {
    final now = DateTime.now();
    final last = _lastPersist;
    if (last != null && now.difference(last) < _persistInterval) return;
    _lastPersist = now;
    unawaited(LocalStore.write(_storeName, snapshot()));
  }
}

final nodeMetrics = NodeMetrics();
