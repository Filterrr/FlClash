import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class ProxiesSetting extends StatelessWidget {
  const ProxiesSetting({super.key});

  String _getStringProxiesSortType(ProxiesSortType type) {
    return switch (type) {
      ProxiesSortType.none => appLocalizations.defaultText,
      ProxiesSortType.delay => appLocalizations.delay,
      ProxiesSortType.name => appLocalizations.name,
      ProxiesSortType.speed => appLocalizations.speed,
    };
  }

  String getTextForProxiesLayout(ProxiesLayout proxiesLayout) {
    return switch (proxiesLayout) {
      ProxiesLayout.tight => appLocalizations.tight,
      ProxiesLayout.standard => appLocalizations.standard,
      ProxiesLayout.loose => appLocalizations.loose,
    };
  }

  String _getTextWithProxiesIconStyle(ProxiesIconStyle style) {
    return switch (style) {
      ProxiesIconStyle.standard => appLocalizations.standard,
      ProxiesIconStyle.none => appLocalizations.noIcon,
      ProxiesIconStyle.icon => appLocalizations.onlyIcon,
    };
  }

  /// 风格磁贴：缩略示意图 + 文案。
  Widget _buildStyleTile({
    required BuildContext context,
    required ProxiesType type,
    required bool isSelected,
    required void Function() onPressed,
  }) {
    final colorScheme = context.colorScheme;
    final isTab = type == ProxiesType.tab;
    return Expanded(
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary.opacity10
                : colorScheme.surfaceContainerHighest.opacity60,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  isSelected ? colorScheme.primary : colorScheme.outlineVariant,
              width: isSelected ? 1.6 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 54,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: colorScheme.outlineVariant.opacity60,
                  ),
                ),
                child: isTab
                    ? Row(
                        children: [
                          for (var index = 0; index < 2; index++) ...[
                            if (index > 0)
                              const SizedBox(
                                width: 4,
                              ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: index == 0
                                            ? colorScheme.primary.opacity60
                                            : colorScheme
                                                .surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(
                                    height: 4,
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color:
                                            colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var index = 0; index < 3; index++) ...[
                            if (index > 0)
                              const SizedBox(
                                height: 4,
                              ),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
              const SizedBox(
                height: 8,
              ),
              Text(
                Intl.message(type.name),
                style: context.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChipBlock<T>({
    required List<T> options,
    required T value,
    required String Function(T value) labelBuilder,
    required void Function(T value) onChanged,
  }) {
    return SettingsSubBlock(
      child: SettingsChips(
        children: [
          for (final item in options)
            SettingsChoiceChip(
              label: labelBuilder(item),
              isSelected: item == value,
              onPressed: () {
                onChanged(item);
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 该页在底部弹层中展示：用单列可滚动容器保持「按内容收缩高度」的行为。
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Selector<Config, ProxiesType>(
            selector: (_, config) => config.proxiesStyle.type,
            builder: (_, proxiesType, __) {
              final config = globalState.appController.config;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SettingsSectionHeader(
                    label: appLocalizations.style,
                    value: Intl.message(proxiesType.name),
                  ),
                  SettingsCard(
                    children: [
                      SettingsSubBlock(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var index = 0;
                                index < ProxiesType.values.length;
                                index++) ...[
                              if (index > 0)
                                const SizedBox(
                                  width: 10,
                                ),
                              _buildStyleTile(
                                context: context,
                                type: ProxiesType.values[index],
                                isSelected:
                                    proxiesType == ProxiesType.values[index],
                                onPressed: () {
                                  config.proxiesStyle =
                                      config.proxiesStyle.copyWith(
                                    type: ProxiesType.values[index],
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          Selector<Config, ProxiesSortType>(
            selector: (_, config) => config.proxiesStyle.sortType,
            builder: (_, proxiesSortType, __) {
              final config = globalState.appController.config;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SettingsSectionHeader(
                    label: appLocalizations.sort,
                    value: _getStringProxiesSortType(proxiesSortType),
                  ),
                  SettingsCard(
                    children: [
                      _buildChipBlock<ProxiesSortType>(
                        options: ProxiesSortType.values,
                        value: proxiesSortType,
                        labelBuilder: _getStringProxiesSortType,
                        onChanged: (value) {
                          config.proxiesStyle = config.proxiesStyle.copyWith(
                            sortType: value,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          Selector<Config, ProxiesLayout>(
            selector: (_, config) => config.proxiesStyle.layout,
            builder: (_, proxiesLayout, __) {
              final config = globalState.appController.config;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SettingsSectionHeader(
                    label: appLocalizations.layout,
                    value: getTextForProxiesLayout(proxiesLayout),
                  ),
                  SettingsCard(
                    children: [
                      _buildChipBlock<ProxiesLayout>(
                        options: ProxiesLayout.values,
                        value: proxiesLayout,
                        labelBuilder: getTextForProxiesLayout,
                        onChanged: (value) {
                          config.proxiesStyle = config.proxiesStyle.copyWith(
                            layout: value,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          Selector<Config, ProxyCardType>(
            selector: (_, config) => config.proxiesStyle.cardType,
            builder: (_, proxyCardType, __) {
              final config = globalState.appController.config;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SettingsSectionHeader(
                    label: appLocalizations.size,
                    value: Intl.message(proxyCardType.name),
                  ),
                  SettingsCard(
                    children: [
                      _buildChipBlock<ProxyCardType>(
                        options: ProxyCardType.values,
                        value: proxyCardType,
                        labelBuilder: (item) => Intl.message(item.name),
                        onChanged: (value) {
                          config.proxiesStyle = config.proxiesStyle.copyWith(
                            cardType: value,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          Selector<Config, bool>(
            selector: (_, config) =>
                config.proxiesStyle.type == ProxiesType.list,
            builder: (_, isList, __) {
              if (!isList) return const SizedBox();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Selector<Config, ProxiesIconStyle>(
                    selector: (_, config) => config.proxiesStyle.iconStyle,
                    builder: (_, iconStyle, __) {
                      final config = globalState.appController.config;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SettingsSectionHeader(
                            label: appLocalizations.iconStyle,
                            value: _getTextWithProxiesIconStyle(iconStyle),
                          ),
                          SettingsCard(
                            children: [
                              _buildChipBlock<ProxiesIconStyle>(
                                options: ProxiesIconStyle.values,
                                value: iconStyle,
                                labelBuilder: _getTextWithProxiesIconStyle,
                                onChanged: (value) {
                                  config.proxiesStyle =
                                      config.proxiesStyle.copyWith(
                                    iconStyle: value,
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  const SettingsBottomSpace(),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
