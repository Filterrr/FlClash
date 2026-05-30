import 'dart:async';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';

class LogsFragment extends StatefulWidget {
  const LogsFragment({super.key});

  @override
  State<LogsFragment> createState() => _LogsFragmentState();
}

class _LogsFragmentState extends State<LogsFragment> {
  final logsNotifier = ValueNotifier<LogsAndKeywords>(const LogsAndKeywords());
  final scrollController = ScrollController(
    keepScrollOffset: false,
  );

  Timer? timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appFlowingState = globalState.appController.appFlowingState;
      logsNotifier.value =
          logsNotifier.value.copyWith(logs: appFlowingState.logs);
      timer?.cancel();
      timer = Timer.periodic(
        globalState.isAppPaused
            ? const Duration(seconds: 5)
            : const Duration(milliseconds: 500),
        (timer) {
          if (globalState.isAppPaused) return;
          final logs = appFlowingState.logs;
          if (!logListEquality.equals(
            logsNotifier.value.logs,
            logs,
          )) {
            logsNotifier.value = logsNotifier.value.copyWith(
              logs: logs,
            );
          }
        },
      );
    });
  }

  @override
  void dispose() {
    super.dispose();
    timer?.cancel();
    logsNotifier.dispose();
    scrollController.dispose();
    timer = null;
  }

  _handleExport() async {
    final commonScaffoldState = context.commonScaffoldState;
    final res = await commonScaffoldState?.loadingRun<bool>(
      () async {
        return await globalState.appController.exportLogs();
      },
      title: appLocalizations.exportLogs,
    );
    if (res != true) return;
    globalState.showMessage(
      title: appLocalizations.tip,
      message: TextSpan(text: appLocalizations.exportSuccess),
    );
  }

  _initActions() {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      final commonScaffoldState =
          context.findAncestorStateOfType<CommonScaffoldState>();
      commonScaffoldState?.actions = [
        IconButton(
          onPressed: () {
            showSearch(
              context: context,
              delegate: LogsSearchDelegate(
                logs: logsNotifier.value,
              ),
            );
          },
          icon: const Icon(Icons.search),
        ),
        const SizedBox(
          width: 8,
        ),
        IconButton(
          onPressed: () {
            _handleExport();
          },
          icon: const Icon(
            Icons.file_download_outlined,
          ),
        ),
      ];
    });
  }

  _addKeyword(String keyword) {
    final isContains = logsNotifier.value.keywords.contains(keyword);
    if (isContains) return;
    final keywords = List<String>.from(logsNotifier.value.keywords)
      ..add(keyword);
    logsNotifier.value = logsNotifier.value.copyWith(
      keywords: keywords,
    );
  }

  _deleteKeyword(String keyword) {
    final isContains = logsNotifier.value.keywords.contains(keyword);
    if (!isContains) return;
    final keywords = List<String>.from(logsNotifier.value.keywords)
      ..remove(keyword);
    logsNotifier.value = logsNotifier.value.copyWith(
      keywords: keywords,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, bool?>(
      selector: (_, appState) =>
          appState.currentLabel == 'logs' ||
          appState.viewMode == ViewMode.mobile &&
              appState.currentLabel == "tools",
      builder: (_, isCurrent, child) {
        if (isCurrent == null || isCurrent) {
          _initActions();
        }
        return child!;
      },
      child: ValueListenableBuilder<LogsAndKeywords>(
        valueListenable: logsNotifier,
        builder: (_, state, __) {
          final logs = state.filteredLogs;
          if (logs.isEmpty) {
            return NullStatus(
              label: appLocalizations.nullLogsDesc,
            );
          }
          final count = logs.length;
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
                    runSpacing: 8,
                    spacing: 8,
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
                child: RepaintBoundary(
                  child: LayoutBuilder(
                    builder: (_, constraints) {
                      return ScrollConfiguration(
                        behavior: ShowBarScrollBehavior(),
                        child: ListView.builder(
                          controller: scrollController,
                          addAutomaticKeepAlives: false,
                          addRepaintBoundaries: true,
                          addSemanticIndexes: false,
                          itemExtentBuilder: (index, __) {
                            if (index % 2 == 1) return 0;
                            final log = logs[count - 1 - (index ~/ 2)];
                            final measure = globalState.measure;
                            final bodyLargeSize = measure.bodyLargeSize;
                            final bodySmallHeight = measure.bodySmallHeight;
                            final bodyMediumHeight = measure.bodyMediumHeight;
                            final width = (log.payload?.length ?? 0) *
                                    bodyLargeSize.width +
                                200;
                            final lines =
                                (width / constraints.maxWidth).ceil();
                            return lines * bodyLargeSize.height +
                                bodySmallHeight +
                                8 +
                                bodyMediumHeight +
                                40;
                          },
                          itemBuilder: (_, index) {
                            if (index % 2 == 1) {
                              return const Divider(height: 0);
                            }
                            final log = logs[count - 1 - (index ~/ 2)];
                            return LogItem(
                              key: ValueKey(log.dateTime.toString()),
                              log: log,
                              onClick: _addKeyword,
                            );
                          },
                          itemCount: count * 2 - 1,
                        ),
                      );
                    },
                  ),
                ),
              )
            ],
          );
        },
      ),
    );
  }
}

class LogsSearchDelegate extends SearchDelegate {
  ValueNotifier<LogsAndKeywords> logsNotifier;
  List<Log> _cachedResults = [];
  String _cachedQuery = '';

  LogsSearchDelegate({
    required LogsAndKeywords logs,
  }) : logsNotifier = ValueNotifier(logs);

  @override
  void dispose() {
    super.dispose();
    logsNotifier.dispose();
  }

  get state => logsNotifier.value;

  List<Log> get _results {
    final lowQuery = query.toLowerCase();
    if (lowQuery == _cachedQuery) return _cachedResults;
    _cachedQuery = lowQuery;
    _cachedResults = logsNotifier.value.filteredLogs
        .where(
          (log) =>
              (log.payload?.toLowerCase().contains(lowQuery) ?? false) ||
              log.logLevel.name.contains(lowQuery),
        )
        .toList();
    return _cachedResults;
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
          _cachedQuery = '';
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

  _addKeyword(String keyword) {
    final isContains = logsNotifier.value.keywords.contains(keyword);
    if (isContains) return;
    final keywords = List<String>.from(logsNotifier.value.keywords)
      ..add(keyword);
    logsNotifier.value = logsNotifier.value.copyWith(
      keywords: keywords,
    );
  }

  _deleteKeyword(String keyword) {
    final isContains = logsNotifier.value.keywords.contains(keyword);
    if (!isContains) return;
    final keywords = List<String>.from(logsNotifier.value.keywords)
      ..remove(keyword);
    logsNotifier.value = logsNotifier.value.copyWith(
      keywords: keywords,
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: logsNotifier,
      builder: (_, __, ___) {
        final results = _results;
        final count = results.length;
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
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
                addSemanticIndexes: false,
                itemBuilder: (_, index) {
                  final log = results[index];
                  return LogItem(
                    key: ValueKey(log.dateTime.toString()),
                    log: log,
                    onClick: (value) {
                      _addKeyword(value);
                    },
                  );
                },
                separatorBuilder: (BuildContext context, int index) {
                  return const Divider(
                    height: 0,
                  );
                },
                itemCount: count,
              ),
            )
          ],
        );
      },
    );
  }
}

class LogItem extends StatefulWidget {
  final Log log;
  final Function(String)? onClick;

  const LogItem({
    super.key,
    required this.log,
    this.onClick,
  });

  @override
  State<LogItem> createState() => _LogItemState();
}

class _LogItemState extends State<LogItem> {
  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    return ListItem(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 4,
      ),
      title: SelectableText(
        log.payload ?? '',
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            "${log.dateTime}",
            style: context.textTheme.bodySmall
                ?.copyWith(color: context.colorScheme.primary),
          ),
          const SizedBox(
            height: 8,
          ),
          Container(
            alignment: Alignment.centerLeft,
            child: CommonChip(
              onPressed: () {
                if (widget.onClick == null) return;
                widget.onClick!(log.logLevel.name);
              },
              label: log.logLevel.name,
            ),
          ),
        ],
      ),
    );
  }
}