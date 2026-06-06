import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum ConnectionGroupAction {
  none,
  process,
  host,
  chain,
}

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

  VisibilityAwareTimer? timer;
  ConnectionGroupMode _groupMode = ConnectionGroupMode.none;
  bool _showStats = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      connectionsNotifier.value = connectionsNotifier.value.copyWith(
        connections: await clashCore.getConnections(),
      );
      _startTimer();
    });
    lowMemoryModeNotifier.addListener(_onLowMemoryModeChanged);
  }

  void _onLowMemoryModeChanged() {
    if (isLowMemoryMode) {
      _stopTimer();
    } else {
      _startTimer();
    }
  }

  void _startTimer() {
    _stopTimer();
    timer = VisibilityAwareTimer(
      interval: isReducedMemoryMode
          ? const Duration(seconds: 10)
          : const Duration(seconds: 1),
      callback: () async {
        if (!context.mounted) return;
        final connections = await clashCore.getConnections();
        connectionsNotifier.value = connectionsNotifier.value.copyWith(
          connections: connections,
        );
      },
      isVisible: () {
        final appState = globalState.appController.appState;
        return appState.currentLabel == 'connections' ||
            (appState.viewMode == ViewMode.mobile &&
                appState.currentLabel == "tools");
      },
    );
    timer!.start();
  }

  void _stopTimer() {
    timer?.stop();
    timer = null;
  }

  _initActions() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        final commonScaffoldState =
            context.findAncestorStateOfType<CommonScaffoldState>();
        commonScaffoldState?.actions = [
          IconButton(
            onPressed: () {
              setState(() {
                _showStats = !_showStats;
              });
            },
            icon: Icon(_showStats ? Icons.bar_chart : Icons.bar_chart_outlined),
            tooltip: appLocalizations.connectionStats,
          ),
          const SizedBox(width: 4),
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
          const SizedBox(width: 4),
          PopupMenuButton<ConnectionGroupAction>(
            icon: const Icon(Icons.folder_open_outlined),
            tooltip: appLocalizations.connectionGroupByProcess,
            onSelected: (action) {
              setState(() {
                _groupMode = switch (action) {
                  ConnectionGroupAction.none => ConnectionGroupMode.none,
                  ConnectionGroupAction.process => ConnectionGroupMode.process,
                  ConnectionGroupAction.host => ConnectionGroupMode.host,
                  ConnectionGroupAction.chain => ConnectionGroupMode.chain,
                };
              });
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: ConnectionGroupAction.none,
                child: Text(appLocalizations.connectionUngrouped),
              ),
              PopupMenuItem(
                value: ConnectionGroupAction.process,
                child: Text(appLocalizations.connectionGroupByProcess),
              ),
              PopupMenuItem(
                value: ConnectionGroupAction.host,
                child: Text(appLocalizations.connectionGroupByHost),
              ),
              PopupMenuItem(
                value: ConnectionGroupAction.chain,
                child: Text(appLocalizations.connectionGroupByChain),
              ),
            ],
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () async {
              clashCore.closeConnections();
              connectionsNotifier.value = connectionsNotifier.value.copyWith(
                connections: await clashCore.getConnections(),
              );
            },
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: _handleExportConnections,
            icon: const Icon(Icons.file_download_outlined),
            tooltip: appLocalizations.exportConnections,
          ),
        ];
      },
    );
  }

  Future<void> _handleExportConnections() async {
    final connections = connectionsNotifier.value.connections;
    final data = await Isolate.run<List<int>>(() {
      final jsonStr = json.encode(connections.map((c) => c.toJson()).toList());
      return utf8.encode(jsonStr);
    });
    final res = await picker.saveFile(
      'connections.json',
      Uint8List.fromList(data),
    );
    if (res != null && mounted) {
      globalState.showMessage(
        title: appLocalizations.tip,
        message: TextSpan(text: appLocalizations.exportSuccess),
      );
    }
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
    _stopTimer();
    connectionsNotifier.dispose();
    _scrollController.dispose();
    lowMemoryModeNotifier.removeListener(_onLowMemoryModeChanged);
  }

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, bool?>(
      selector: (_, appState) =>
          appState.currentLabel == 'connections' ||
          appState.viewMode == ViewMode.mobile &&
              appState.currentLabel == "tools",
      builder: (_, isCurrent, child) {
        if (isCurrent == null || isCurrent) {
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
              if (_showStats)
                ConnectionStatsPanel(connections: connections),
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
                child: _groupMode == ConnectionGroupMode.none
                    ? ListView.separated(
                        controller: _scrollController,
                        itemBuilder: (_, index) {
                          final connection = connections[index];
                          return ConnectionItem(
                            key: Key(connection.id),
                            connection: connection,
                            onClick: _addKeyword,
                            trailing: IconButton(
                              icon: const Icon(Icons.block),
                              onPressed: () {
                                _handleBlockConnection(connection.id);
                              },
                            ),
                          );
                        },
                        separatorBuilder: (BuildContext context, int index) {
                          return const Divider(height: 0);
                        },
                        itemCount: connections.length,
                      )
                    : _buildGroupedListView(connections),
              )
            ],
          );
        },
      ),
    );
  }

  Widget _buildGroupedListView(List<Connection> connections) {
    final groups = groupConnections(connections, _groupMode);
    final groupNames = groups.keys.toList();
    return ListView.builder(
      controller: _scrollController,
      itemCount: groupNames.length,
      itemBuilder: (_, groupIndex) {
        final groupName = groupNames[groupIndex];
        final groupConnections = groups[groupName]!;
        return ExpansionTile(
          initiallyExpanded: true,
          title: Text(
            '$groupName (${groupConnections.length})',
            style: context.textTheme.titleSmall,
          ),
          children: [
            for (final connection in groupConnections)
              ConnectionItem(
                key: Key(connection.id),
                connection: connection,
                onClick: _addKeyword,
                trailing: IconButton(
                  icon: const Icon(Icons.block),
                  onPressed: () {
                    _handleBlockConnection(connection.id);
                  },
                ),
              ),
          ],
        );
      },
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
                    trailing: IconButton(
                      icon: const Icon(Icons.block),
                      onPressed: () {
                        _handleBlockConnection(connection.id);
                      },
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
