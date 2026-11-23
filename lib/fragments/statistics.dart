import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/services/node_metrics.dart';
import 'package:fl_clash/services/traffic_statistics.dart';
import 'package:flutter/material.dart';

/// 流量统计页:今日 / 昨日 / 本月 + 最近 14 天趋势。
///
/// 数据来自 [TrafficStatistics],源头是 core 的累计总流量。
class StatisticsFragment extends StatefulWidget {
  const StatisticsFragment({super.key});

  @override
  State<StatisticsFragment> createState() => _StatisticsFragmentState();
}

class _StatisticsFragmentState extends State<StatisticsFragment> {
  DailyTraffic _today = DailyTraffic();
  DailyTraffic _yesterday = DailyTraffic();
  DailyTraffic _month = DailyTraffic();
  List<MapEntry<String, DailyTraffic>> _recent = [];
  List<String> _nodeNames = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final today = await trafficStatistics.trafficOf();
    final yesterday = await trafficStatistics.trafficOf(
      DateTime.now().subtract(const Duration(days: 1)),
    );
    final month = await trafficStatistics.monthTotal();
    final recent = await trafficStatistics.recent(14);
    final nodeNames = nodeMetrics.orderedNames();
    if (!mounted) return;
    setState(() {
      _today = today;
      _yesterday = yesterday;
      _month = month;
      _recent = recent;
      _nodeNames = nodeNames;
      _loading = false;
    });
  }

  static String _formatBytes(int value) {
    if (value <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var index = 0;
    var size = value.toDouble();
    while (size >= 1024 && index < units.length - 1) {
      size /= 1024;
      index++;
    }
    return '${size.toStringAsFixed(index == 0 ? 0 : 2)} ${units[index]}';
  }

  Widget _summaryCard() {
    final colorScheme = Theme.of(context).colorScheme;
    Widget item(String label, DailyTraffic traffic) {
      return Expanded(
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatBytes(traffic.total),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '↑ ${_formatBytes(traffic.up)}  ↓ ${_formatBytes(traffic.down)}',
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Row(
          children: [
            item('今日', _today),
            item('昨日', _yesterday),
            item('本月', _month),
          ],
        ),
      ),
    );
  }

  Widget _chartCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final maxValue = _recent.fold<int>(
      0,
      (prev, e) => e.value.total > prev ? e.value.total : prev,
    );
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '最近 14 天',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 96,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final entry in _recent)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Tooltip(
                          message:
                              '${entry.key}\n${_formatBytes(entry.value.total)}',
                          child: Container(
                            height: maxValue <= 0
                                ? 2
                                : (entry.value.total / maxValue * 88)
                                    .clamp(2, 88)
                                    .toDouble(),
                            decoration: BoxDecoration(
                              color: entry.value.total <= 0
                                  ? colorScheme.outlineVariant
                                  : colorScheme.primary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _recent.isEmpty ? '' : _recent.first.key.substring(5),
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  _recent.isEmpty ? '' : _recent.last.key.substring(5),
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _nodeQualityCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '节点质量',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '按最近延迟排序,最多显示 20 个',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            if (_nodeNames.isEmpty)
              Text(
                '还没有测速记录。到代理页测一次速就会开始积累。',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final name in _nodeNames.take(20))
                _buildNodeRow(name, colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildNodeRow(String name, ColorScheme colorScheme) {
    final latest = nodeMetrics.latestDelay(name);
    final average = nodeMetrics.averageDelay(name);
    final jitter = nodeMetrics.jitter(name);
    final rate = nodeMetrics.successRate(name);
    final details = <String>[];
    if (average != null) details.add('均值 $average ms');
    if (jitter != null) details.add('抖动 $jitter ms');
    if (rate != null) details.add('成功率 ${(rate * 100).round()}%');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                if (details.isNotEmpty)
                  Text(
                    details.join(' · '),
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            latest == null ? '超时' : '$latest ms',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: latest == null ? colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.only(top: 0, bottom: 24),
      children: [
        _summaryCard(),
        _chartCard(),
        _nodeQualityCard(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            '统计基于 core 的累计流量,每 30 秒采样一次。'
            '进程重启或手动重置后从零开始,后台挂起期间的量会在恢复时补齐。',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('刷新'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  await trafficStatistics.clear();
                  await _load();
                },
                child: const Text('清空统计'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}