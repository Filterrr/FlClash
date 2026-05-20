import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/fragments/proxies/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ProxyCard extends StatelessWidget {
  final String groupName;
  final Proxy proxy;
  final GroupType groupType;
  final ProxyCardType type;

  const ProxyCard({
    super.key,
    required this.groupName,
    required this.proxy,
    required this.groupType,
    required this.type,
  });

  Measure get measure => globalState.measure;

  void _handleTestCurrentDelay() {
    proxyDelayTest(proxy);
  }

  Widget _buildDelayText() {
    return SizedBox(
      height: measure.labelSmallHeight,
      child: Selector<AppState, int?>(
        selector: (context, appState) => appState.getDelay(
          proxy.name,
        ),
        builder: (context, delay, __) {
          return FadeThroughBox(
            alignment: type == ProxyCardType.expand
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: delay == 0 || delay == null
                ? SizedBox(
                    height: measure.labelSmallHeight,
                    width: measure.labelSmallHeight,
                    child: delay == 0
                        ? const CircularProgressIndicator(strokeWidth: 2)
                        : IconButton(
                            icon: const Icon(Icons.bolt),
                            iconSize: globalState.measure.labelSmallHeight,
                            padding: EdgeInsets.zero,
                            onPressed: _handleTestCurrentDelay,
                          ),
                  )
                : GestureDetector(
                    onTap: _handleTestCurrentDelay,
                    child: Text(
                      delay > 0 ? "$delay ms" : "Timeout",
                      style: context.textTheme.labelSmall?.copyWith(
                        overflow: TextOverflow.ellipsis,
                        color: other.getDelayColor(delay),
                      ),
                    ),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildProxyNameText(BuildContext context) {
    if (type == ProxyCardType.min) {
      return SizedBox(
        height: measure.bodyMediumHeight * 1,
        child: EmojiText(
          proxy.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.bodyMedium,
        ),
      );
    } else {
      return SizedBox(
        height: measure.bodyMediumHeight * 2,
        child: EmojiText(
          proxy.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.bodyMedium,
        ),
      );
    }
  }

  Future<void> _changeProxy(BuildContext context) async {
    final isURLTestOrFallback = groupType.isURLTestOrFallback;
    final isSelector = groupType == GroupType.Selector;
    if (isURLTestOrFallback || isSelector) {
      final currentProxyName =
          globalState.appController.config.currentSelectedMap[groupName];
      final nextProxyName = switch (isURLTestOrFallback) {
        true => currentProxyName == proxy.name ? "" : proxy.name,
        false => proxy.name,
      };
      globalState.appController.config.updateCurrentSelectedMap(
        groupName,
        nextProxyName,
      );
      globalState.appController.changeProxyDebounce([
        groupName,
        nextProxyName,
      ]);
      return;
    }
    globalState.showSnackBar(
      context,
      message: appLocalizations.notSelectedTip,
    );
  }

  @override
  Widget build(BuildContext context) {
    final measure = globalState.measure;
    final delayText = _buildDelayText();
    final proxyNameText = _buildProxyNameText(context);
    return Stack(
      children: [
        currentSelectedProxyNameBuilder(
          groupName: groupName,
          builder: (currentGroupName) {
            return CommonCard(
              key: key,
              onPressed: () {
                _changeProxy(context);
              },
              isSelected: currentGroupName == proxy.name,
              child: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    proxyNameText,
                    const SizedBox(height: 8),
                    if (type == ProxyCardType.expand) ...[
                      SizedBox(
                        height: measure.bodySmallHeight,
                        child: _ProxyDesc(proxy: proxy),
                      ),
                      const SizedBox(height: 6),
                      delayText,
                    ] else
                      SizedBox(
                        height: measure.bodySmallHeight,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              flex: 1,
                              child: TooltipText(
                                text: Text(
                                  proxy.type,
                                  style: context.textTheme.bodySmall?.copyWith(
                                    overflow: TextOverflow.ellipsis,
                                    color: context.textTheme.bodySmall?.color
                                        ?.opacity80,
                                  ),
                                ),
                              ),
                            ),
                            delayText,
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        if (groupType.isURLTestOrFallback)
          _ProxyComputedMark(groupName: groupName, proxy: proxy)
      ],
    );
  }
}

class _ProxyDesc extends StatelessWidget {
  final Proxy proxy;

  const _ProxyDesc({required this.proxy});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, String>(
      selector: (_, appState) => appState.getDesc(
        proxy.type,
        proxy.name,
      ),
      builder: (_, desc, __) {
        return EmojiText(
          desc,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.bodySmall?.copyWith(
            color: context.textTheme.bodySmall?.color?.opacity80,
          ),
        );
      },
    );
  }
}

class _ProxyComputedMark extends StatelessWidget {
  final String groupName;
  final Proxy proxy;

  const _ProxyComputedMark({required this.groupName, required this.proxy});

  @override
  Widget build(BuildContext context) {
    return Selector<Config, String>(
      selector: (_, config) {
        final proxyName = config.currentSelectedMap[groupName];
        return proxyName ?? '';
      },
      builder: (_, proxyName, child) {
        if (proxyName != proxy.name) {
          return const SizedBox();
        }
        return child!;
      },
      child: Positioned(
        top: 0,
        right: 0,
        child: Container(
          alignment: Alignment.topRight,
          margin: const EdgeInsets.all(8),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.secondaryContainer,
            ),
            child: const SelectIcon(),
          ),
        ),
      ),
    );
  }
}
