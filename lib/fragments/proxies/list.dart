import 'dart:math';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'card.dart';
import 'common.dart';

typedef GroupNameProxiesMap = Map<String, List<Proxy>>;

enum _ListItemType { header, spacer, proxyRow }

class _ListItemDescriptor {
  final _ListItemType type;
  final String? groupName;
  final int? rowIndex;
  final int? totalRows;
  final List<Proxy>? rowProxies;
  final GroupType? groupType;
  final bool? isExpand;

  const _ListItemDescriptor({
    required this.type,
    this.groupName,
    this.rowIndex,
    this.totalRows,
    this.rowProxies,
    this.groupType,
    this.isExpand,
  });
}

class ProxiesListFragment extends StatefulWidget {
  const ProxiesListFragment({super.key});

  @override
  State<ProxiesListFragment> createState() => _ProxiesListFragmentState();
}

class _ProxiesListFragmentState extends State<ProxiesListFragment> {
  final _controller = ScrollController();
  final _headerStateNotifier = ValueNotifier<ProxiesListHeaderSelectorState>(
    const ProxiesListHeaderSelectorState(
      offset: 0,
      currentIndex: 0,
    ),
  );
  List<double> _headerOffset = [];
  GroupNameProxiesMap _lastGroupNameProxiesMap = {};

  @override
  void initState() {
    super.initState();
    _controller.addListener(_adjustHeader);
  }

  _adjustHeader() {
    final offset = _controller.offset;
    final index = _headerOffset.findInterval(offset);
    final currentIndex = index;
    double headerOffset = 0.0;
    if (index + 1 <= _headerOffset.length - 1) {
      final endOffset = _headerOffset[index + 1];
      final startOffset = endOffset - listHeaderHeight - 8;
      if (offset > startOffset && offset < endOffset) {
        headerOffset = offset - startOffset;
      }
    }
    _headerStateNotifier.value = _headerStateNotifier.value.copyWith(
      currentIndex: currentIndex,
      offset: max(headerOffset, 0),
    );
  }

  double _getItemHeight(_ListItemDescriptor item, ProxyCardType proxyCardType) {
    return switch (item.type) {
      _ListItemType.spacer => 8,
      _ListItemType.header => listHeaderHeight,
      _ListItemType.proxyRow => getItemHeight(proxyCardType),
    };
  }

  @override
  void dispose() {
    super.dispose();
    _headerStateNotifier.dispose();
    _controller.removeListener(_adjustHeader);
    _controller.dispose();
  }

  _handleChange(Set<String> currentUnfoldSet, String groupName) {
    final tempUnfoldSet = Set<String>.from(currentUnfoldSet);
    if (tempUnfoldSet.contains(groupName)) {
      tempUnfoldSet.remove(groupName);
    } else {
      tempUnfoldSet.add(groupName);
    }
    globalState.appController.config.updateCurrentUnfoldSet(
      tempUnfoldSet,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _adjustHeader();
    });
  }

  List<double> _computeItemHeights(
    List<_ListItemDescriptor> descriptors,
    ProxyCardType proxyCardType,
  ) {
    final itemHeightList = <double>[];
    List<double> headerOffset = [];
    double currentHeight = 0;
    for (int i = 0; i < descriptors.length; i++) {
      final item = descriptors[i];
      if (item.type == _ListItemType.header) {
        headerOffset.add(currentHeight);
      }
      final itemHeight = _getItemHeight(item, proxyCardType);
      itemHeightList.add(itemHeight);
      currentHeight += itemHeight;
    }
    _headerOffset = headerOffset;
    return itemHeightList;
  }

  List<_ListItemDescriptor> _buildDescriptors({
    required List<String> groupNames,
    required int columns,
    required Set<String> currentUnfoldSet,
    required ProxyCardType type,
  }) {
    final descriptors = <_ListItemDescriptor>[];
    final GroupNameProxiesMap groupNameProxiesMap = {};
    for (final groupName in groupNames) {
      final group =
          globalState.appController.appState.getGroupWithName(groupName)!;
      final isExpand = currentUnfoldSet.contains(groupName);
      descriptors.add(_ListItemDescriptor(
        type: _ListItemType.header,
        groupName: groupName,
        isExpand: isExpand,
        groupType: group.type,
      ));
      descriptors.add(const _ListItemDescriptor(type: _ListItemType.spacer));
      if (isExpand) {
        final sortedProxies = globalState.appController.getSortProxies(
          group.all,
        );
        groupNameProxiesMap[groupName] = sortedProxies;
        final chunks = sortedProxies.chunks(columns);
        for (int rowIdx = 0; rowIdx < chunks.length; rowIdx++) {
          descriptors.add(_ListItemDescriptor(
            type: _ListItemType.proxyRow,
            groupName: groupName,
            rowIndex: rowIdx,
            totalRows: chunks.length,
            rowProxies: chunks[rowIdx],
            groupType: group.type,
          ));
          if (rowIdx < chunks.length - 1) {
            descriptors.add(const _ListItemDescriptor(type: _ListItemType.spacer));
          }
        }
        descriptors.add(const _ListItemDescriptor(type: _ListItemType.spacer));
      }
    }
    _lastGroupNameProxiesMap = groupNameProxiesMap;
    return descriptors;
  }

  Widget _buildItemFromDescriptor(
    _ListItemDescriptor descriptor,
    int columns,
    ProxyCardType type,
    Set<String> currentUnfoldSet,
  ) {
    switch (descriptor.type) {
      case _ListItemType.header:
        return ListHeader(
          onScrollToSelected: _scrollToGroupSelected,
          key: Key(descriptor.groupName!),
          isExpand: descriptor.isExpand!,
          group: globalState.appController.appState
              .getGroupWithName(descriptor.groupName!)!,
          onChange: (String groupName) {
            _handleChange(currentUnfoldSet, groupName);
          },
        );
      case _ListItemType.spacer:
        return const SizedBox(height: 8);
      case _ListItemType.proxyRow:
        final proxies = descriptor.rowProxies!;
        final groupName = descriptor.groupName!;
        final groupType = descriptor.groupType!;
        final children = proxies
            .map<Widget>(
              (proxy) => Flexible(
                child: ProxyCard(
                  type: type,
                  groupType: groupType,
                  key: ValueKey('$groupName.${proxy.name}'),
                  proxy: proxy,
                  groupName: groupName,
                ),
              ),
            )
            .fill(
              columns,
              filler: (_) => const Flexible(child: SizedBox()),
            )
            .separated(const SizedBox(width: 8));
        return Row(children: children.toList());
    }
  }

  _buildHeader({
    required String groupName,
    required Set<String> currentUnfoldSet,
  }) {
    final group =
        globalState.appController.appState.getGroupWithName(groupName)!;
    final isExpand = currentUnfoldSet.contains(groupName);
    return SizedBox(
      height: listHeaderHeight,
      child: ListHeader(
        onScrollToSelected: _scrollToGroupSelected,
        key: Key(groupName),
        isExpand: isExpand,
        group: group,
        onChange: (String groupName) {
          _handleChange(currentUnfoldSet, groupName);
        },
      ),
    );
  }

  _scrollToGroupSelected(String groupName) {
    if (_controller.position.maxScrollExtent == 0) {
      return;
    }
    final appController = globalState.appController;
    final currentGroups = appController.appState.currentGroups;
    final groupNames = currentGroups.map((e) => e.name).toList();
    final findIndex = groupNames.indexWhere((item) => item == groupName);
    final index = findIndex != -1 ? findIndex : 0;
    final currentInitOffset = _headerOffset[index];
    final proxies = _lastGroupNameProxiesMap[groupName];
    _controller.animateTo(
      min(
        currentInitOffset +
            8 +
            getScrollToSelectedOffset(
              groupName: groupName,
              proxies: proxies ?? [],
            ),
        _controller.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeIn,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Selector2<AppState, Config, ProxiesListSelectorState>(
      selector: (_, appState, config) {
        final currentGroups = appState.currentGroups;
        final groupNames = currentGroups.map((e) => e.name).toList();
        return ProxiesListSelectorState(
          groupNames: groupNames,
          currentUnfoldSet: config.currentUnfoldSet,
          proxyCardType: config.proxiesStyle.cardType,
          proxiesSortType: config.proxiesStyle.sortType,
          columns: other.getProxiesColumns(
            appState.viewWidth,
            config.proxiesStyle.layout,
          ),
          sortNum: appState.sortNum,
        );
      },
      shouldRebuild: (prev, next) {
        if (!stringListEquality.equals(prev.groupNames, next.groupNames)) {
          _headerStateNotifier.value = const ProxiesListHeaderSelectorState(
            offset: 0,
            currentIndex: 0,
          );
        }
        return prev != next;
      },
      builder: (_, state, __) {
        final descriptors = _buildDescriptors(
          groupNames: state.groupNames,
          currentUnfoldSet: state.currentUnfoldSet,
          columns: state.columns,
          type: state.proxyCardType,
        );
        final itemsOffset = _computeItemHeights(descriptors, state.proxyCardType);
        return Scrollbar(
          controller: _controller,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 8,
          radius: const Radius.circular(8),
          interactive: true,
          child: Stack(
            children: [
              Positioned.fill(
                child: ScrollConfiguration(
                  behavior: HiddenBarScrollBehavior(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    controller: _controller,
                    itemExtentBuilder: (index, __) {
                      return itemsOffset[index];
                    },
                    itemCount: descriptors.length,
                    itemBuilder: (_, index) {
                      return _buildItemFromDescriptor(
                        descriptors[index],
                        state.columns,
                        state.proxyCardType,
                        state.currentUnfoldSet,
                      );
                    },
                  ),
                ),
              ),
              LayoutBuilder(builder: (_, container) {
                return ValueListenableBuilder(
                  valueListenable: _headerStateNotifier,
                  builder: (_, headerState, ___) {
                    final index =
                        headerState.currentIndex > state.groupNames.length - 1
                            ? 0
                            : headerState.currentIndex;
                    if (index < 0 || state.groupNames.isEmpty) {
                      return Container();
                    }
                    return Stack(
                      children: [
                        Positioned(
                          top: -headerState.offset,
                          child: Container(
                            width: container.maxWidth,
                            color: context.colorScheme.surface,
                            padding: const EdgeInsets.only(
                              top: 16,
                              left: 16,
                              right: 16,
                              bottom: 8,
                            ),
                            child: _buildHeader(
                              groupName: state.groupNames[index],
                              currentUnfoldSet: state.currentUnfoldSet,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class ListHeader extends StatefulWidget {
  final Group group;

  final Function(String groupName) onChange;
  final Function(String groupName) onScrollToSelected;
  final bool isExpand;

  const ListHeader({
    super.key,
    required this.group,
    required this.onChange,
    required this.onScrollToSelected,
    required this.isExpand,
  });

  @override
  State<ListHeader> createState() => _ListHeaderState();
}

class _ListHeaderState extends State<ListHeader> {
  var isLock = false;

  String get icon => widget.group.icon;

  String get groupName => widget.group.name;

  String get groupType => widget.group.type.name;

  bool get isExpand => widget.isExpand;

  _delayTest(List<Proxy> proxies) async {
    if (isLock) return;
    isLock = true;
    await delayTest(proxies);
    isLock = false;
  }

  _handleChange(String groupName) {
    widget.onChange(groupName);
  }

  Widget _buildIcon() {
    return Selector<Config, ProxiesIconStyle>(
      selector: (_, config) => config.proxiesStyle.iconStyle,
      builder: (_, iconStyle, child) {
        return Selector<Config, String>(
          selector: (_, config) {
            final iconMapEntryList =
                config.proxiesStyle.iconMap.entries.toList();
            final index = iconMapEntryList.indexWhere((item) {
              try {
                return RegExp(item.key).hasMatch(groupName);
              } catch (_) {
                return false;
              }
            });
            if (index != -1) {
              return iconMapEntryList[index].value;
            }
            return icon;
          },
          builder: (_, icon, __) {
            return switch (iconStyle) {
              ProxiesIconStyle.standard => LayoutBuilder(
                  builder: (_, constraints) {
                    return Container(
                      margin: const EdgeInsets.only(right: 16),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Container(
                          height: constraints.maxHeight,
                          width: constraints.maxWidth,
                          alignment: Alignment.center,
                          padding: EdgeInsets.all(6.ap),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: context.colorScheme.secondaryContainer,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: CommonIcon(
                            src: icon,
                            size: constraints.maxHeight - 12.ap,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ProxiesIconStyle.icon => Container(
                  margin: const EdgeInsets.only(right: 16),
                  child: LayoutBuilder(
                    builder: (_, constraints) {
                      return CommonIcon(
                        src: icon,
                        size: constraints.maxHeight - 8,
                      );
                    },
                  ),
                ),
              ProxiesIconStyle.none => Container(),
            };
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonCard(
      key: widget.key,
      radius: 18.ap,
      type: CommonCardType.filled,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Row(
                children: [
                  _buildIcon(),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        EmojiText(
                          groupName,
                          style: context.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Flexible(
                          flex: 1,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                groupType,
                                style:
                                    context.textTheme.labelMedium?.toLight,
                              ),
                              Flexible(
                                flex: 1,
                                child: currentSelectedProxyNameBuilder(
                                  groupName: groupName,
                                  builder: (currentGroupName) {
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        if (currentGroupName.isNotEmpty) ...[
                                          Flexible(
                                            flex: 1,
                                            child: EmojiText(
                                              overflow: TextOverflow.ellipsis,
                                              ' · $currentGroupName',
                                              style: context
                                                  .textTheme
                                                  .labelMedium
                                                  ?.toLight,
                                            ),
                                          ),
                                        ],
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                if (isExpand) ...[
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.all(2),
                    onPressed: () {
                      widget.onScrollToSelected(groupName);
                    },
                    style: ButtonStyle(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    iconSize: 19,
                    icon: const Icon(Icons.adjust),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.all(2),
                    onPressed: () {
                      _delayTest(widget.group.all);
                    },
                    style: ButtonStyle(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.network_ping),
                  ),
                  const SizedBox(width: 6),
                ] else
                  SizedBox(width: 6),
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.all(2),
                  iconSize: 24,
                  style: ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    _handleChange(groupName);
                  },
                  icon: CommonExpandIcon(expand: isExpand),
                ),
              ],
            ),
          ],
        ),
      ),
      onPressed: () {
        _handleChange(groupName);
      },
    );
  }
}
