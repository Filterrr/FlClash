import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 按应用分流(进程规则)编辑器。
///
/// mihomo 一直支持 `PROCESS-NAME` 规则,但 UI 从来没给过入口 ——
/// 这一页把「选应用 -> 选目标 -> 拿到规则文本」这条链路补上。
///
/// 有意**不**自动注入配置:那要扩 `ConfigExtendedParams`(codegen 模型,
/// 得同步生成文件)并在 core 侧新开一个 override 口子,风险和收益不成比例。
/// 这里先生成规则文本,用户贴进自己配置的 rules 段即可 —— 半自动,
/// 但绝不会悄悄改坏别人的配置。
class AppRoutingFragment extends StatefulWidget {
  const AppRoutingFragment({super.key});

  @override
  State<AppRoutingFragment> createState() => _AppRoutingFragmentState();
}

class _AppRoutingFragmentState extends State<AppRoutingFragment> {
  static const String _storeName = 'app_routing.json';

  List<Package> _packages = [];
  List<String> _groups = [];
  Map<String, String> _routing = {};
  bool _loading = true;
  bool _showSystem = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final packages = await app?.getPackages() ?? <Package>[];
    List<String> groups = [];
    try {
      final proxies = await clashCore.getProxiesGroups();
      groups = proxies
          .where((e) => e.hidden != true && e.name.isNotEmpty)
          .map((e) => e.name)
          .toList();
    } catch (_) {
      // core 没起来也要能用:退化成只有内置目标可选
    }
    final raw = await LocalStore.read(_storeName);
    final routing = <String, String>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        if (key is String && value is String) routing[key] = value;
      });
    }
    if (!mounted) return;
    setState(() {
      _packages = packages;
      _groups = groups;
      _routing = routing;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await LocalStore.write(_storeName, _routing);
  }

  List<String> get _targets => [..._groups, 'DIRECT', 'REJECT'];

  Future<void> _pickTarget(Package package) async {
    final current = _routing[package.packageName];
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '${package.label} 走哪里',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              title: const Text('跟随规则(不设置)'),
              trailing: current == null ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(''),
            ),
            for (final target in _targets)
              ListTile(
                title: Text(target),
                trailing: current == target ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(target),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    setState(() {
      if (selected.isEmpty) {
        _routing.remove(package.packageName);
      } else {
        _routing[package.packageName] = selected;
      }
    });
    await _save();
  }

  String _buildRulesText() {
    if (_routing.isEmpty) return '';
    // 稳定排序,免得每次复制出来的顺序都不一样
    final entries = _routing.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries
        .map((e) => 'PROCESS-NAME,${e.key},${e.value}')
        .join('\n');
  }

  Future<void> _showRules() async {
    final text = _buildRulesText();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有为任何应用指定目标')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '规则文本',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                '复制后贴到配置的 rules 段(放在通用规则之前才生效)',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectableText(
                    text,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: text));
                      if (!mounted) return;
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('复制'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _packages
        .where((e) => _showSystem || !e.isSystem)
        .toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '已指定 ${_routing.length} 个应用',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _showSystem = !_showSystem),
                icon: Icon(
                  _showSystem ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                ),
                label: Text(_showSystem ? '隐藏系统应用' : '显示系统应用'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: _showRules,
                icon: const Icon(Icons.rule, size: 18),
                label: const Text('生成规则'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _routing.isEmpty
                    ? null
                    : () async {
                        setState(() => _routing = {});
                        await _save();
                      },
                child: const Text('全部清除'),
              ),
            ],
          ),
        ),
        const Divider(height: 20),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (_, index) {
                    final package = visible[index];
                    final target = _routing[package.packageName];
                    return ListTile(
                      title: Text(package.label),
                      subtitle: Text(package.packageName),
                      trailing: Text(
                        target ?? '跟随规则',
                        style: TextStyle(
                          fontSize: 13,
                          color: target == null
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      onTap: () => _pickTarget(package),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
