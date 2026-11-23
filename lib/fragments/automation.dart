import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/services/automation_service.dart';
import 'package:fl_clash/services/profile_snapshot.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';

/// 自动化设置:定时测速 / 优选 / 网络变化触发 / 配置回滚。
///
/// 文案暂未接入 arb,理由同诊断页 —— 先让功能跑起来,文案稳定后再补。
class AutomationFragment extends StatefulWidget {
  const AutomationFragment({super.key});

  @override
  State<AutomationFragment> createState() => _AutomationFragmentState();
}

class _AutomationFragmentState extends State<AutomationFragment> {
  AutomationConfig _config = AutomationConfig();
  List<String> _groups = [];
  bool _loading = true;
  bool _testing = false;
  DateTime? _snapshotTime;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await automationService.load();
    List<String> groups = [];
    try {
      final proxies = await clashCore.getProxiesGroups();
      groups = proxies
          .where((e) => e.hidden != true && e.type == GroupType.Selector)
          .map((e) => e.name)
          .toList();
    } catch (_) {}
    final profileId = globalState.appController.config.currentProfileId;
    final time = profileId == null
        ? null
        : await ProfileSnapshotService.snapshotTime(profileId);
    if (!mounted) return;
    setState(() {
      _config = automationService.config;
      _groups = groups;
      _snapshotTime = time;
      _loading = false;
    });
  }

  Future<void> _persist() async {
    await automationService.apply();
    if (!mounted) return;
    setState(() => _config = automationService.config);
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '暂无快照';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  Widget _sectionCard(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      children: [
        _sectionCard('定时测速', [
          SwitchListTile(
            title: const Text('启用定时测速'),
            subtitle: const Text('只在 App 前台生效'),
            value: _config.autoTestEnabled,
            onChanged: (value) {
              _config.autoTestEnabled = value;
              _persist();
            },
          ),
          if (_config.autoTestEnabled) ...[
            ListTile(
              title: const Text('测速间隔'),
              subtitle: Slider(
                min: 1,
                max: 120,
                divisions: 119,
                value: _config.intervalMinutes
                    .clamp(1, 120)
                    .toDouble(),
                label: '${_config.intervalMinutes} 分钟',
                onChanged: (value) {
                  setState(() => _config.intervalMinutes = value.round());
                },
                onChangeEnd: (_) => _persist(),
              ),
              trailing: Text('${_config.intervalMinutes} 分'),
            ),
            ListTile(
              title: const Text('目标策略组'),
              subtitle: Text(_config.groupName ?? '未指定(全部 Selector 组)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _groups.isEmpty
                  ? null
                  : () async {
                      final selected = await showModalBottomSheet<String>(
                        context: context,
                        showDragHandle: true,
                        builder: (_) => SafeArea(
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              ListTile(
                                title: const Text('全部 Selector 组'),
                                onTap: () => Navigator.of(context).pop(''),
                              ),
                              for (final name in _groups)
                                ListTile(
                                  title: Text(name),
                                  onTap: () => Navigator.of(context).pop(name),
                                ),
                            ],
                          ),
                        ),
                      );
                      if (selected == null) return;
                      _config.groupName =
                          selected.isEmpty ? null : selected;
                      await _persist();
                    },
            ),
            SwitchListTile(
              title: const Text('自动切换到最快节点'),
              subtitle: Text(
                '连续 ${_config.switchStreak} 次最快的节点才切 —— '
                '单次测速抖动大,立刻切会让节点反复横跳',
              ),
              value: _config.autoSwitch,
              onChanged: (value) {
                _config.autoSwitch = value;
                _persist();
              },
            ),
          ],
        ]),
        _sectionCard('网络变化', [
          SwitchListTile(
            title: const Text('切换网络时自动重测'),
            subtitle: const Text('WiFi <-> 蜂窝切换后历史延迟基本作废,立即重测一轮'),
            value: _config.triggerOnNetworkChange,
            onChanged: (value) {
              _config.triggerOnNetworkChange = value;
              _persist();
            },
          ),
        ]),
        _sectionCard('立即执行', [
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('测速一轮(可自动切换)'),
            subtitle: const Text('手动跑一次上面的策略'),
            trailing: _testing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _testing
                ? null
                : () async {
                    setState(() => _testing = true);
                    final delays = await automationService.testOnce();
                    if (!mounted) return;
                    setState(() => _testing = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('完成,共测 ${delays.length} 个节点'),
                      ),
                    );
                  },
          ),
        ]),
        _sectionCard('配置回滚', [
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('订阅快照'),
            subtitle: Text('更新前自动留一份 · ${_formatTime(_snapshotTime)}'),
          ),
          ListTile(
            leading: Icon(Icons.restore, color: colorScheme.primary),
            title: const Text('恢复到上一版配置'),
            subtitle: const Text('用快照覆盖当前订阅配置'),
            onTap: _snapshotTime == null
                ? null
                : () async {
                    final profileId =
                        globalState.appController.config.currentProfileId;
                    if (profileId == null) return;
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('恢复上一版配置?'),
                        content: const Text(
                          '当前订阅配置会被快照覆盖。恢复后建议重新应用一次配置。',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('恢复'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    final ok = await ProfileSnapshotService.restore(profileId);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(ok ? '已恢复' : '恢复失败')),
                    );
                  },
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            '定时器只在 App 前台运行(Flutter 的 Timer 在后台会被系统挂起)。'
            '需要真正的常驻自动化,得下沉到原生侧。',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
