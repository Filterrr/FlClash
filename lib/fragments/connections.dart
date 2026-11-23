import 'dart:async';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/manager/background_memory_manager.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'background_polling_strategy.dart';

class ConnectionsFragment extends StatefulWidget {
  const ConnectionsFragment({super.key});

  @override
  State<ConnectionsFragment> createState() => _ConnectionsFragmentState();
}

class _ConnectionsFragmentState extends State<ConnectionsFragment> {
  final connectionsNotifier =
      ValueNotifier<ConnectionsAndKeywords>(const ConnectionsAndKeywords());
  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: false,
  );

  Timer? timer;
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      connectionsNotifier.value = connectionsNotifier.value.copyWith(
        connections: await clashCore.getConnections(),
      );
      _syncTimerWithState();
    });
    lowMemoryModeNotifier.addListener(_onLowMemoryModeChanged);
    backgroundMemoryManager.addListener(_onBackgroundStateChanged);
  }

  void _onBackgroundStateChanged() {
    _syncTimerWithState();
  }

  void _onLowMemoryModeChanged() {
    _syncTimerWithState();
  }

  void _syncTimerWithState() {
    final pollingMode = resolvePollingMode(
      isVisible: _isVisible,
      isInBackground: backgroundMemoryManager.isInBackground,
      lowMemoryMode: lowMemoryModeNotifier.value,
    );

    if (pollingMode == PollingMode.stopped) {
      _stopTimer();
    } else if (pollingMode == PollingMode.reduced) {
      _startReducedTimer();
    } else {
      _startTimer();
    }
  }

  void _onVisibilityChanged(bool visible) {
    if (_isVisible == visible) return;
    _isVisible = visible;
    _syncTimerWithState();
  }

  void _startTimer() {
    _stopTimer();
    // 2s 而不是 1s:这里是「全量连接列表 -> 序列化 -> 跨 FFI 传输 ->
    // Dart 侧 json.decode」的完整链路,连接数上百时每次都是 MB 级分配。
    // 间隔翻倍在观感上几乎无差别,功耗与内存抖动却是实打实减半。
    timer = Timer.periodic(
      const Duration(seconds: 2),
      (timer) async {
        if (!context.mounted) {
          return;
        }
        connectionsNotifier.value = connectionsNotifier.value.copyWith(
          connections: await clashCore.getConnections(),
        );
      },
    );
  }

  void _startReducedTimer() {
    _stopTimer();
    timer = Timer.periodic(
      const Duration(seconds: 10),
      (timer) async {
        if (!context.mounted) {
          return;
        }
        connectionsNotifier.value = connectionsNotifier.value.copyWith(
          connections: await clashCore.getConnections(),
        );
      },
    );
  }

  void _showConnectionDetail(Connection connection) {
    final extra =
        connectionExtraStore[connection.id] ?? ConnectionExtra.empty;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ConnectionDetailSheet(
        connection: connection,
        extra: extra,
      ),
    );
  }

  void _stopTimer() {
    if (timer != null) {
      timer?.cancel();
      timer = null;
    }
  }

  _initActions() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        final commonScaffoldState =
            context.findAncestorStateOfType<CommonScaffoldState>();
        commonScaffoldState?.actions = [
          IconButton(
            onPressed: () {
              showSearch(
                context: context,
                delegate: ConnectionsSearchDelegate(
                  state: connectionsNotifier.value,
                ),
              );
            },
            icon: const Icon(Icons.search),
          ),
          const SizedBox(
            width: 8,
          ),
          IconButton(
            onPressed: () async {
              clashCore.closeConnections();
              connectionsNotifier.value = connectionsNotifier.value.copyWith(
                connections: await clashCore.getConnections(),
              );
            },
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ];
      },
    );
  }

  _addKeyword(String keyword) {
    final isContains = connectionsNotifier.value.keywords.contains(keyword);
    if (isContains) return;
    final keywords = List<String>.from(connectionsNotifier.value.keywords)
      ..add(keyword);
    connectionsNotifier.value = connectionsNotifier.value.copyWith(
      keywords: keywords,
    );
  }

  _deleteKeyword(String keyword) {
    final isContains = connectionsNotifier.value.keywords.contains(keyword);
    if (!isContains) return;
    final keywords = List<String>.from(connectionsNotifier.value.keywords)
      ..remove(keyword);
    connectionsNotifier.value = connectionsNotifier.value.copyWith(
      keywords: keywords,
    );
  }

  _handleBlockConnection(String id) async {
    clashCore.closeConnection(id);
    connectionsNotifier.value = connectionsNotifier.value.copyWith(
      connections: await clashCore.getConnections(),
    );
  }

  @override
  void dispose() {
    super.dispose();
    timer?.cancel();
    connectionsNotifier.dispose();
    _scrollController.dispose();
    lowMemoryModeNotifier.removeListener(_onLowMemoryModeChanged);
    backgroundMemoryManager.removeListener(_onBackgroundStateChanged);
    timer = null;
  }

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, bool?>(
      selector: (_, appState) =>
          appState.currentLabel == 'connections' ||
          appState.viewMode == ViewMode.mobile &&
              appState.currentLabel == "tools",
      builder: (_, isCurrent, child) {
        final visible = isCurrent == null || isCurrent;
        _onVisibilityChanged(visible);
        if (visible) {
          _initActions();
        }
        return child!;
      },
      child: ValueListenableBuilder<ConnectionsAndKeywords>(
        valueListenable: connectionsNotifier,
        builder: (_, state, __) {
          var connections = state.filteredConnections;
          if (connections.isEmpty) {
            return NullStatus(
              label: appLocalizations.nullConnectionsDesc,
            );
          }
          connections = connections.reversed.toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state.keywords.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Wrap(
                    runSpacing: 6,
                    spacing: 6,
                    children: [
                      for (final keyword in state.keywords)
                        CommonChip(
                          label: keyword,
                          type: ChipType.delete,
                          onPressed: () {
                            _deleteKeyword(keyword);
                          },
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  controller: _scrollController,
                  itemBuilder: (_, index) {
                    final connection = connections[index];
                    return ConnectionItem(
                      key: Key(connection.id),
                      connection: connection,
                      onClick: _addKeyword,
                        trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          IconButton(
                            icon: const Icon(Icons.info_outline),
                            tooltip: '详情',
                            onPressed: () => _showConnectionDetail(connection),
                          ),
                          IconButton(
                            icon: const Icon(Icons.block),
                            onPressed: () {
                              _handleBlockConnection(connection.id);
                            },
                          ),
                            ],
                        ),
                    );
                  },
                  separatorBuilder: (BuildContext context, int index) {
                    return const Divider(
                      height: 0,
                    );
                  },
                  itemCount: connections.length,
                ),
              )
            ],
          );
        },
      ),
    );
  }
}

class ConnectionsSearchDelegate extends SearchDelegate {
  ValueNotifier<ConnectionsAndKeywords> connectionsNotifier;

  ConnectionsSearchDelegate({
    required ConnectionsAndKeywords state,
  }) : connectionsNotifier = ValueNotifier<ConnectionsAndKeywords>(state);

  get state => connectionsNotifier.value;

  List<Connection> get _results {
    final lowerQuery = query.toLowerCase().trim();
    return connectionsNotifier.value.filteredConnections.where((request) {
      final lowerNetwork = request.metadata.network.toLowerCase();
      final lowerHost = request.metadata.host.toLowerCase();
      final lowerDestinationIP = request.metadata.destinationIP.toLowerCase();
      final lowerProcess = request.metadata.process.toLowerCase();
      final lowerChains = request.chains.join("").toLowerCase();
      return lowerNetwork.contains(lowerQuery) ||
          lowerHost.contains(lowerQuery) ||
          lowerDestinationIP.contains(lowerQuery) ||
          lowerProcess.contains(lowerQuery) ||
          lowerChains.contains(lowerQuery);
    }).toList();
  }

  _addKeyword(String keyword) {
    final isContains = connectionsNotifier.value.keywords.contains(keyword);
    if (isContains) return;
    final keywords = List<String>.from(connectionsNotifier.value.keywords)
      ..add(keyword);
    connectionsNotifier.value = connectionsNotifier.value.copyWith(
      keywords: keywords,
    );
  }

  _deleteKeyword(String keyword) {
    final isContains = connectionsNotifier.value.keywords.contains(keyword);
    if (!isContains) return;
    final keywords = List<String>.from(connectionsNotifier.value.keywords)
      ..remove(keyword);
    connectionsNotifier.value = connectionsNotifier.value.copyWith(
      keywords: keywords,
    );
  }

  _handleBlockConnection(String id) async {
    clashCore.closeConnection(id);
    connectionsNotifier.value = connectionsNotifier.value.copyWith(
      connections: await clashCore.getConnections(),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        onPressed: () {
          if (query.isEmpty) {
            close(context, null);
            return;
          }
          query = '';
        },
        icon: const Icon(Icons.clear),
      ),
      const SizedBox(
        width: 8,
      )
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      onPressed: () {
        close(context, null);
      },
      icon: const Icon(Icons.arrow_back),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return buildSuggestions(context);
  }

  @override
  void dispose() {
    connectionsNotifier.dispose();
    super.dispose();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: connectionsNotifier,
      builder: (_, __, ___) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.keywords.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Wrap(
                  runSpacing: 6,
                  spacing: 6,
                  children: [
                    for (final keyword in state.keywords)
                      CommonChip(
                        label: keyword,
                        type: ChipType.delete,
                        onPressed: () {
                          _deleteKeyword(keyword);
                        },
                      ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.separated(
                itemBuilder: (_, index) {
                  final connection = _results[index];
                  return ConnectionItem(
                    key: Key(connection.id),
                    connection: connection,
                    onClick: _addKeyword,
                      trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        IconButton(
                          icon: const Icon(Icons.info_outline),
                          tooltip: '详情',
                          onPressed: () => _showConnectionDetail(connection),
                        ),
                        IconButton(
                          icon: const Icon(Icons.block),
                          onPressed: () {
                            _handleBlockConnection(connection.id);
                          },
                        ),
                          ],
                      ),
                  );
                },
                separatorBuilder: (BuildContext context, int index) {
                  return const Divider(
                    height: 0,
                  );
                },
                itemCount: _results.length,
              ),
            )
          ],
        );
      },
    );
  }
}

/// 单条连接的完整元数据面板。
///
/// 数据分两处取:基础字段一直在 Connection.metadata 里;
/// 规则命中 / ASN / GeoIP / 进程路径来自旁挂的 ConnectionExtra
/// (core 返回里本来就有,只是 codegen 模型没解析)。
class _ConnectionDetailSheet extends StatelessWidget {
  final Connection connection;
  final ConnectionExtra extra;

  const _ConnectionDetailSheet({
    required this.connection,
    required this.extra,
  });

  String get _ruleText {
    if (extra.rule.isEmpty) return '';
    if (extra.rulePayload.isEmpty) return extra.rule;
    return '${extra.rule},${extra.rulePayload}';
  }

  Widget _row(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
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

  @override
  Widget build(BuildContext context) {
    final metadata = connection.metadata;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              '连接详情',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _row('目标 IP', metadata.destinationIP),
            _row('域名', metadata.host),
            _row('端口', metadata.destinationPort),
            _row('网络', metadata.network),
            _row('来源', metadata.sourceIP),
            _row('进程', metadata.process),
            _row('进程路径', extra.processPath),
            _row('SNI', extra.sniffHost),
            _row('DNS 模式', extra.dnsMode),
            _row('命中规则', _ruleText),
            _row('目标 ASN', extra.destinationIPASN),
            _row('目标地区', extra.destinationGeoIP.join(', ')),
            _row('来源 ASN', extra.sourceIPASN),
            _row('来源地区', extra.sourceGeoIP.join(', ')),
            _row('特殊规则', extra.specialRules),
            _row('特殊代理', extra.specialProxy),
            _row('链路', connection.chains.join(' -> ')),
          ],
        ),
      ),
    );
  }
}
