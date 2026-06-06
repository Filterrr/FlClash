import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/material.dart';

/// 连接统计面板：展示总连接数、上传/下载流量、TOP 主机/进程
class ConnectionStatsPanel extends StatelessWidget {
  final List<Connection> connections;

  const ConnectionStatsPanel({
    super.key,
    required this.connections,
  });

  @override
  Widget build(BuildContext context) {
    final stats = _computeStats();
    final textTheme = context.textTheme;
    final colorScheme = context.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appLocalizations.connectionStats,
            style: textTheme.titleSmall?.copyWith(
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          _buildSummaryRow(context, stats),
          if (stats.topHosts.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildTopList(
              context: context,
              title: 'TOP Hosts',
              items: stats.topHosts,
            ),
          ],
          if (stats.topProcesses.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildTopList(
              context: context,
              title: 'TOP Processes',
              items: stats.topProcesses,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryRow(BuildContext context, _ConnectionStats stats) {
    return Row(
      children: [
        _buildStatItem(
          context,
          label: appLocalizations.totalConnections,
          value: '${stats.totalCount}',
        ),
        const SizedBox(width: 16),
        _buildStatItem(
          context,
          label: appLocalizations.totalUpload,
          value: TrafficValue(value: stats.totalUpload).show,
        ),
        const SizedBox(width: 16),
        _buildStatItem(
          context,
          label: appLocalizations.totalDownload,
          value: TrafficValue(value: stats.totalDownload).show,
        ),
      ],
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.textTheme.labelSmall?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: context.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildTopList({
    required BuildContext context,
    required String title,
    required List<MapEntry<String, int>> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: context.textTheme.labelSmall?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: items.map((e) {
            return Chip(
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              label: Text('${e.key} (${e.value})'),
              labelStyle: context.textTheme.labelSmall,
            );
          }).toList(),
        ),
      ],
    );
  }

  _ConnectionStats _computeStats() {
    int totalCount = connections.length;
    num totalUpload = 0;
    num totalDownload = 0;
    final hostCount = <String, int>{};
    final processCount = <String, int>{};

    for (final conn in connections) {
      totalUpload += conn.upload ?? 0;
      totalDownload += conn.download ?? 0;
      final host = conn.metadata.host;
      if (host.isNotEmpty) {
        hostCount[host] = (hostCount[host] ?? 0) + 1;
      }
      final process = conn.metadata.process;
      if (process.isNotEmpty) {
        processCount[process] = (processCount[process] ?? 0) + 1;
      }
    }

    final topHosts = hostCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topProcesses = processCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _ConnectionStats(
      totalCount: totalCount,
      totalUpload: totalUpload,
      totalDownload: totalDownload,
      topHosts: topHosts.take(5).toList(),
      topProcesses: topProcesses.take(5).toList(),
    );
  }
}

class _ConnectionStats {
  final int totalCount;
  final num totalUpload;
  final num totalDownload;
  final List<MapEntry<String, int>> topHosts;
  final List<MapEntry<String, int>> topProcesses;

  _ConnectionStats({
    required this.totalCount,
    required this.totalUpload,
    required this.totalDownload,
    required this.topHosts,
    required this.topProcesses,
  });
}

/// 连接分组模式
enum ConnectionGroupMode {
  none,
  process,
  host,
  chain,
}

/// 按指定模式对连接进行分组
Map<String, List<Connection>> groupConnections(
  List<Connection> connections,
  ConnectionGroupMode mode,
) {
  switch (mode) {
    case ConnectionGroupMode.none:
      return {appLocalizations.connectionUngrouped: connections};
    case ConnectionGroupMode.process:
      final groups = <String, List<Connection>>{};
      for (final conn in connections) {
        final key = conn.metadata.process.isEmpty
            ? appLocalizations.connectionUngrouped
            : conn.metadata.process;
        groups.putIfAbsent(key, () => []).add(conn);
      }
      return groups;
    case ConnectionGroupMode.host:
      final groups = <String, List<Connection>>{};
      for (final conn in connections) {
        final key = conn.metadata.host.isEmpty
            ? conn.metadata.destinationIP
            : conn.metadata.host;
        groups.putIfAbsent(key, () => []).add(conn);
      }
      return groups;
    case ConnectionGroupMode.chain:
      final groups = <String, List<Connection>>{};
      for (final conn in connections) {
        final key = conn.chains.isEmpty
            ? appLocalizations.connectionUngrouped
            : conn.chains.join(' → ');
        groups.putIfAbsent(key, () => []).add(conn);
      }
      return groups;
  }
}
