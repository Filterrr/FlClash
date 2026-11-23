import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';

/// 诊断工具页:分流诊断 + core 运行时健康状况。
///
/// 这一页暂时只提供中文文案,未接入 arb —— 它是排障工具,
/// 等文案稳定后再补 l10n,免得现在往十几个语言文件里塞半成品。
class DiagnosticsFragment extends StatefulWidget {
  const DiagnosticsFragment({super.key});

  @override
  State<DiagnosticsFragment> createState() => _DiagnosticsFragmentState();
}

class _DiagnosticsFragmentState extends State<DiagnosticsFragment> {
  final TextEditingController _controller = TextEditingController();

  RuleMatchResult? _result;
  bool _checking = false;
  String? _error;

  CoreMemoryStats _stats = CoreMemoryStats.empty;
  bool _loadingStats = false;

  List<Log> _dnsLogs = [];

  @override
  void initState() {
    super.initState();
    _refreshStats();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refreshStats() async {
    setState(() => _loadingStats = true);
    final stats = await clashCore.getMemoryStats();
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _loadingStats = false;
      _dnsLogs = _collectDnsLogs();
    });
  }

  /// 从 core 推上来的日志里挑出 DNS 相关行。
  ///
  /// 用宽松匹配(大小写无关地找 "dns")而不是死抠 `[DNS]` 前缀 ——
  /// mihomo 各版本的 DNS 日志措辞会变,抠死了就静默什么都看不到。
  /// 前提是「日志」开关是打开的,core 不推送就没有数据。
  List<Log> _collectDnsLogs() {
    try {
      final logs = globalState.appController.appFlowingState.logs;
      final matched = logs
          .where((e) => (e.payload ?? '').toLowerCase().contains('dns'))
          .toList();
      // 新的在上面
      return matched.reversed.take(60).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _check() async {
    final target = _controller.text.trim();
    if (target.isEmpty) {
      setState(() {
        _error = '请输入域名、IP 或 host:port';
        _result = null;
      });
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    final result = await clashCore.matchRule(target);
    if (!mounted) return;
    setState(() {
      _result = result;
      _checking = false;
    });
  }

  static String _formatBytes(int value) {
    if (value <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var index = 0;
    var size = value.toDouble();
    while (size >= 1024 && index < units.length - 1) {
      size /= 1024;
      index++;
    }
    return '${size.toStringAsFixed(index == 0 ? 0 : 1)} ${units[index]}';
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleChecker() {
    final result = _result;
    return _buildCard(
      title: '分流诊断',
      icon: Icons.alt_route,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              hintText: 'example.com / 1.2.3.4 / example.com:8443',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _check(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _checking ? null : _check,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('诊断'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  _controller.clear();
                  setState(() {
                    _result = null;
                    _error = null;
                  });
                },
                child: const Text('清空'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (result != null) ...[
            const Divider(height: 24),
            if (!result.matched)
              const Text('没有命中任何规则。检查配置里是否有 MATCH 兜底。')
            else ...[
              _buildRow('命中规则', result.rule),
              if (result.payload.isNotEmpty) _buildRow('匹配内容', result.payload),
              _buildRow('落点', result.adapter),
              const SizedBox(height: 8),
              SelectableText(
                result.ruleText,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildCoreHealth() {
    return _buildCard(
      title: '核心运行时',
      icon: Icons.memory,
      trailing: IconButton(
        onPressed: _loadingStats ? null : _refreshStats,
        icon: const Icon(Icons.refresh, size: 20),
        tooltip: '刷新',
      ),
      child: _stats.isEmpty
          ? Text(
              _loadingStats ? '读取中…' : '暂无数据(core 可能尚未启动)',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRow('堆在用', _formatBytes(_stats.heapAlloc)),
                _buildRow('堆申请', _formatBytes(_stats.heapSys)),
                _buildRow('已归还系统', _formatBytes(_stats.heapReleased)),
                _buildRow('进程总内存', _formatBytes(_stats.sys)),
                _buildRow('GC 次数', '${_stats.numGC}'),
                _buildRow('强制 GC', '${_stats.numForcedGC}'),
                _buildRow(
                  'GC CPU 占比',
                  '${(_stats.gcCPUFraction * 100).toStringAsFixed(2)} %',
                ),
              ],
            ),
    );
  }

  Widget _buildDnsPanel() {
    final colorScheme = Theme.of(context).colorScheme;
    return _buildCard(
      title: 'DNS 解析',
      icon: Icons.dns_outlined,
      trailing: IconButton(
        onPressed: () => setState(() => _dnsLogs = _collectDnsLogs()),
        icon: const Icon(Icons.refresh, size: 20),
        tooltip: '刷新',
      ),
      child: _dnsLogs.isEmpty
          ? Text(
              '暂无 DNS 日志。需要在设置里打开「日志」开关,core 才会推送。',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '最近 ${_dnsLogs.length} 条(来自 core 日志)',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                for (final log in _dnsLogs.take(40))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: SelectableText(
                      log.payload ?? '',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        _buildRuleChecker(),
        _buildCoreHealth(),
        _buildDnsPanel(),
      ],
    );
  }
}
