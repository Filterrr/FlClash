import 'dart:async';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';

/// 每日流量统计。
///
/// 数据源是 core 的**累计**总流量(`statistic.TotalTraffic`),不是瞬时速度。
/// 这一点很关键:因为是累计值,「后台没采样」不会丢量 —— 恢复后一次采样
/// 就能把中间攒下的差额补回来。如果拿速度累加,后台挂起期间就真丢了。
///
/// 进程重启或用户手动重置后,core 的累计值会归零,差值出现负数,按
/// 「从零开始」处理。
class TrafficStatistics {
  static const String _storeName = 'traffic_daily.json';

  /// 两次采样之间的最小间隔。
  ///
  /// `updateTraffic` 前台 1s 一次、后台 10s 一次,但累计值的变化不需要
  /// 这么细的粒度;30s 一次既够准,又省掉大量无谓的 FFI 往返与落盘。
  static const Duration _minInterval = Duration(seconds: 30);

  /// 只保留最近 N 天,免得文件无限长。
  static const int _retainDays = 60;

  Map<String, DailyTraffic> _daily = {};
  bool _loaded = false;
  bool _primed = false;
  int _lastUp = 0;
  int _lastDown = 0;
  DateTime? _lastSampleAt;
  bool _sampling = false;

  /// 采样并按日累加。可安全地高频调用 —— 内部自带节流与重入保护。
  Future<void> sample() async {
    if (_sampling) return;
    final now = DateTime.now();
    final last = _lastSampleAt;
    if (last != null && now.difference(last) < _minInterval) return;
    _sampling = true;
    _lastSampleAt = now;
    try {
      await _ensureLoaded();
      final Traffic total;
      try {
        total = await clashCore.getTotalTraffic(false);
      } catch (_) {
        return;
      }
      final up = total.up.value.toInt();
      final down = total.down.value.toInt();

      if (!_primed) {
        // 首次采样只记基线:此刻的累计值是从进程启动算起的,
        // 把它整笔算进「今天」会把历史流量误报成今天的。
        _primed = true;
        _lastUp = up;
        _lastDown = down;
        return;
      }

      var deltaUp = up - _lastUp;
      var deltaDown = down - _lastDown;
      if (deltaUp < 0) deltaUp = up;
      if (deltaDown < 0) deltaDown = down;
      _lastUp = up;
      _lastDown = down;

      if (deltaUp <= 0 && deltaDown <= 0) return;

      final key = _dayKey(now);
      final entry = _daily.putIfAbsent(key, () => DailyTraffic());
      entry.up += deltaUp;
      entry.down += deltaDown;
      _prune(now);
      await _persist();
    } finally {
      _sampling = false;
    }
  }

  /// 读取某个日期(默认今天)的流量。
  Future<DailyTraffic> trafficOf([DateTime? day]) async {
    await _ensureLoaded();
    return _daily[_dayKey(day ?? DateTime.now())] ?? DailyTraffic();
  }

  /// 最近 N 天的数据,按日期升序。
  Future<List<MapEntry<String, DailyTraffic>>> recent(int days) async {
    await _ensureLoaded();
    final now = DateTime.now();
    final result = <MapEntry<String, DailyTraffic>>[];
    for (var i = days - 1; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final key = _dayKey(day);
      result.add(MapEntry(key, _daily[key] ?? DailyTraffic()));
    }
    return result;
  }

  Future<DailyTraffic> monthTotal() async {
    await _ensureLoaded();
    final now = DateTime.now();
    final prefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final total = DailyTraffic();
    _daily.forEach((key, value) {
      if (key.startsWith(prefix)) {
        total.up += value.up;
        total.down += value.down;
      }
    });
    return total;
  }

  Future<void> clear() async {
    _daily = {};
    await LocalStore.write(_storeName, const <String, dynamic>{});
  }

  static String _dayKey(DateTime time) {
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    return '${time.year}-$month-$day';
  }

  void _prune(DateTime now) {
    if (_daily.length <= _retainDays) return;
    final keys = _daily.keys.toList()..sort();
    final cutoff = keys.length - _retainDays;
    for (var i = 0; i < cutoff; i++) {
      _daily.remove(keys[i]);
    }
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final raw = await LocalStore.read(_storeName);
    if (raw is Map) {
      final parsed = <String, DailyTraffic>{};
      raw.forEach((key, value) {
        if (key is String && value is Map) {
          parsed[key] = DailyTraffic.fromJson(
            Map<String, dynamic>.from(value),
          );
        }
      });
      _daily = parsed;
    }
  }

  Future<void> _persist() async {
    await LocalStore.write(
      _storeName,
      _daily.map((key, value) => MapEntry(key, value.toJson())),
    );
  }
}

final trafficStatistics = TrafficStatistics();
