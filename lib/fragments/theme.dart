import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/widgets.dart';

class ThemeModeItem {
  final ThemeMode themeMode;
  final IconData iconData;
  final String label;

  const ThemeModeItem({
    required this.themeMode,
    required this.iconData,
    required this.label,
  });
}

class FontFamilyItem {
  final FontFamily fontFamily;
  final String label;

  const FontFamilyItem({
    required this.fontFamily,
    required this.label,
  });
}

ThemeModeItem _getThemeModeItem(ThemeMode themeMode) {
  return switch (themeMode) {
    ThemeMode.system => ThemeModeItem(
        themeMode: ThemeMode.system,
        iconData: Icons.brightness_auto_outlined,
        label: appLocalizations.auto,
      ),
    ThemeMode.light => ThemeModeItem(
        themeMode: ThemeMode.light,
        iconData: Icons.light_mode_outlined,
        label: appLocalizations.light,
      ),
    ThemeMode.dark => ThemeModeItem(
        themeMode: ThemeMode.dark,
        iconData: Icons.dark_mode_outlined,
        label: appLocalizations.dark,
      ),
  };
}

/// 主题预览：用当前主题色渲染的迷你界面。
class ThemePreview extends StatelessWidget {
  const ThemePreview({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(settingsCardRadius),
          border: Border.all(
            color: colorScheme.outlineVariant.opacity60,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primaryContainer.opacity60,
              colorScheme.surfaceContainerLow,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    appName,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.opacity12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    appLocalizations.preview,
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 14,
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: colorScheme.outlineVariant.opacity60,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          appLocalizations.status,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.opacity12,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          appLocalizations.proxies,
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: 0.62,
                      minHeight: 6,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          appLocalizations.download,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        appLocalizations.upload,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      appLocalizations.status,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ThemeFragment extends StatelessWidget {
  const ThemeFragment({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 8),
      children: [
        const ThemePreview(),
        SettingsSectionHeader(label: appLocalizations.themeMode),
        SettingsCard(
          children: [
            Selector<Config, ThemeMode>(
              selector: (_, config) => config.themeProps.themeMode,
              builder: (_, themeMode, __) {
                return SettingsSubBlock(
                  caption: appLocalizations.themeMode,
                  captionValue: _getThemeModeItem(themeMode).label,
                  child: SettingsSegmented<ThemeMode>(
                    options: ThemeMode.values,
                    value: themeMode,
                    labelBuilder: (mode) => _getThemeModeItem(mode).label,
                    iconBuilder: (mode) => _getThemeModeItem(mode).iconData,
                    onChanged: (mode) {
                      final appController = globalState.appController;
                      appController.config.themeProps =
                          appController.config.themeProps.copyWith(
                        themeMode: mode,
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
        Selector<Config, int?>(
          selector: (_, config) => config.themeProps.primaryColor,
          builder: (_, currentPrimaryColor, __) {
            final brightness = Theme.of(context).brightness;
            final systemSeed = globalState
                .appController.appState.systemColorSchemes
                .getSystemColorSchemeForBrightness(brightness)
                .primary;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SettingsSectionHeader(
                  label: appLocalizations.themeColor,
                  value: currentPrimaryColor == null
                      ? appLocalizations.auto
                      : null,
                ),
                SettingsCard(
                  children: [
                    SettingsSubBlock(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SettingsColorSwatch(
                            seedColor: systemSeed,
                            isSelected: currentPrimaryColor == null,
                            overlayIcon: const Icon(Icons.colorize),
                            onPressed: () {
                              final appController = globalState.appController;
                              appController.config.themeProps =
                                  appController.config.themeProps.copyWith(
                                primaryColor: null,
                              );
                            },
                          ),
                          for (final color in defaultPrimaryColors)
                            SettingsColorSwatch(
                              seedColor: Color(color),
                              isSelected: currentPrimaryColor == color,
                              onPressed: () {
                                final appController = globalState.appController;
                                appController.config.themeProps =
                                    appController.config.themeProps.copyWith(
                                  primaryColor: color,
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        SettingsSectionHeader(label: appLocalizations.fontFamily),
        SettingsCard(
          children: [
            Selector<Config, FontFamily>(
              selector: (_, config) => config.themeProps.fontFamily,
              builder: (_, fontFamily, __) {
                final fontFamilyItems = [
                  FontFamilyItem(
                    label: appLocalizations.systemFont,
                    fontFamily: FontFamily.system,
                  ),
                  const FontFamilyItem(
                    label: "MiSans",
                    fontFamily: FontFamily.miSans,
                  ),
                ];
                return SettingsSubBlock(
                  child: SettingsChips(
                    children: [
                      for (final item in fontFamilyItems)
                        SettingsChoiceChip(
                          label: item.label,
                          isSelected: fontFamily == item.fontFamily,
                          onPressed: () {
                            final appController = globalState.appController;
                            appController.config.themeProps =
                                appController.config.themeProps.copyWith(
                              fontFamily: item.fontFamily,
                            );
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        SettingsSectionHeader(label: appLocalizations.interfaceSection),
        SettingsCard(
          children: [
            Selector<Config, bool>(
              selector: (_, config) => config.themeProps.prueBlack,
              builder: (_, value, ___) {
                return ListItem.switchItem(
                  isSettings: true,
                  title: Text(appLocalizations.prueBlackMode),
                  subtitle: Text(appLocalizations.prueBlackModeDesc),
                  delegate: SwitchDelegate(
                    value: value,
                    onChanged: (value) {
                      final appController = globalState.appController;
                      appController.config.themeProps =
                          appController.config.themeProps.copyWith(
                        prueBlack: value,
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
        const SettingsBottomSpace(),
      ],
    );
  }
}
