import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/fragments/about.dart';
import 'package:fl_clash/fragments/access.dart';
import 'package:fl_clash/fragments/application_setting.dart';
import 'package:fl_clash/fragments/config/config.dart';
import 'package:fl_clash/fragments/app_routing.dart';
import 'package:fl_clash/fragments/diagnostics.dart';
import 'package:fl_clash/fragments/hotkey.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'backup_and_recovery.dart';
import 'theme.dart';
import 'package:path/path.dart' show dirname, join;

class ToolsFragment extends StatefulWidget {
  const ToolsFragment({super.key});

  @override
  State<ToolsFragment> createState() => _ToolboxFragmentState();
}

class _ToolboxFragmentState extends State<ToolsFragment> {
  _buildNavigationMenuItem(NavigationItem navigationItem) {
    return ListItem.open(
      leading: navigationItem.icon,
      title: Text(Intl.message(navigationItem.label)),
      subtitle: navigationItem.description != null
          ? Text(Intl.message(navigationItem.description!))
          : null,
      delegate: OpenDelegate(
        title: Intl.message(navigationItem.label),
        widget: navigationItem.fragment,
      ),
    );
  }

  Widget _buildNavigationMenu(List<NavigationItem> navigationItems) {
    return SettingsCard(
      dividerIndentWithIcon: true,
      children: [
        for (final navigationItem in navigationItems)
          _buildNavigationMenuItem(navigationItem),
      ],
    );
  }

  String _getLocaleString(Locale? locale) {
    if (locale == null) return appLocalizations.defaultText;
    return Intl.message(locale.toString());
  }

  String _getLocaleSubtitle(String? localeString) {
    return Intl.message(localeString ?? appLocalizations.defaultText);
  }

  Widget _buildThemeItem() {
    return Selector<Config, ThemeMode>(
      selector: (_, config) => config.themeProps.themeMode,
      builder: (_, themeMode, __) {
        final themeModeText = switch (themeMode) {
          ThemeMode.system => appLocalizations.auto,
          ThemeMode.light => appLocalizations.light,
          ThemeMode.dark => appLocalizations.dark,
        };
        return ListItem.open(
          iconData: Icons.palette_outlined,
          title: Text(appLocalizations.theme),
          subtitle: Text(appLocalizations.themeDesc),
          valueText: themeModeText,
          delegate: OpenDelegate(
            title: appLocalizations.theme,
            widget: const ThemeFragment(),
            extendPageWidth: 360,
          ),
        );
      },
    );
  }

  Widget _buildBackupItem() {
    return Selector<Config, String>(
      selector: (_, config) =>
          config.dav?.fileName ?? appLocalizations.pleaseBindWebDAV,
      builder: (_, value, __) {
        return ListItem.open(
          iconData: Icons.cloud_sync_outlined,
          title: Text(appLocalizations.backupAndRecovery),
          subtitle: Text(appLocalizations.backupAndRecoveryDesc),
          valueText: value,
          delegate: OpenDelegate(
            title: appLocalizations.backupAndRecovery,
            widget: const BackupAndRecovery(),
          ),
        );
      },
    );
  }

  Widget _buildAccessItem() {
    return Selector<Config, AccessControlMode>(
      selector: (_, config) => config.accessControl.mode,
      builder: (_, mode, __) {
        return ListItem.open(
          iconData: Icons.shield_outlined,
          title: Text(appLocalizations.accessControl),
          subtitle: Text(appLocalizations.accessControlDesc),
          valueText: mode == AccessControlMode.acceptSelected
              ? appLocalizations.whitelistMode
              : appLocalizations.blacklistMode,
          delegate: OpenDelegate(
            title: appLocalizations.appAccessControl,
            widget: const AccessFragment(),
          ),
        );
      },
    );
  }

  List<Widget> _getAppearanceSection() {
    return [
      SettingsSection(
        label: appLocalizations.appearance,
        dividerIndentWithIcon: true,
        children: [
          _buildThemeItem(),
          Selector<Config, String?>(
            selector: (_, config) => config.appSetting.locale,
            builder: (_, localeString, __) {
              final currentLocale = other.getLocaleForString(localeString);
              return ListItem<Locale?>.options(
                iconData: Icons.language_outlined,
                title: Text(appLocalizations.language),
                subtitle: Text(_getLocaleSubtitle(localeString)),
                valueText: _getLocaleSubtitle(localeString),
                delegate: OptionsDelegate(
                  title: appLocalizations.language,
                  options: [
                    null,
                    ...AppLocalizations.delegate.supportedLocales
                  ],
                  onChanged: (Locale? value) {
                    final config = globalState.appController.config;
                    config.appSetting = config.appSetting.copyWith(
                      locale: value?.toString(),
                    );
                  },
                  textBuilder: (locale) => _getLocaleString(locale),
                  value: currentLocale,
                ),
              );
            },
          ),
        ],
      )
    ];
  }

  List<Widget> _getConnectionSection() {
    return [
      SettingsSection(
        label: appLocalizations.connectionSection,
        dividerIndentWithIcon: true,
        children: [
          ListItem.open(
            iconData: Icons.tune,
            title: Text(appLocalizations.override),
            subtitle: Text(appLocalizations.overrideDesc),
            delegate: OpenDelegate(
              title: appLocalizations.override,
              widget: const ConfigFragment(),
            ),
          ),
          if (Platform.isAndroid) _buildAccessItem(),
        ],
      )
    ];
  }

  List<Widget> _getSystemSection() {
    final items = <Widget>[
      Selector<Config, BackgroundOptimizationLevel>(
        selector: (_, config) => config.appSetting.backgroundOptimizationLevel,
        builder: (_, level, __) {
          final levelText = switch (level) {
            BackgroundOptimizationLevel.disabled =>
              appLocalizations.backgroundOptimizationLevel_disabled,
            BackgroundOptimizationLevel.light =>
              appLocalizations.backgroundOptimizationLevel_light,
            BackgroundOptimizationLevel.balanced =>
              appLocalizations.backgroundOptimizationLevel_balanced,
            BackgroundOptimizationLevel.aggressive =>
              appLocalizations.backgroundOptimizationLevel_aggressive,
          };
          return ListItem.open(
            iconData: Icons.settings_outlined,
            title: Text(appLocalizations.application),
            subtitle: Text(appLocalizations.applicationDesc),
            valueText: levelText,
            delegate: OpenDelegate(
              title: appLocalizations.application,
              widget: const ApplicationSettingFragment(),
            ),
          );
        },
      ),
      if (system.isDesktop)
        ListItem.open(
          iconData: Icons.keyboard_outlined,
          title: Text(appLocalizations.hotkeyManagement),
          subtitle: Text(appLocalizations.hotkeyManagementDesc),
          delegate: OpenDelegate(
            title: appLocalizations.hotkeyManagement,
            widget: const HotKeyFragment(),
          ),
        ),
      if (Platform.isWindows)
        ListItem(
          iconData: Icons.lock_outline,
          title: Text(appLocalizations.loopback),
          subtitle: Text(appLocalizations.loopbackDesc),
          onTap: () {
            windows?.runas(
              '"${join(dirname(Platform.resolvedExecutable), "EnableLoopback.exe")}"',
              "",
            );
          },
        ),
    ];
    return [
      SettingsSection(
        label: appLocalizations.systemSection,
        dividerIndentWithIcon: true,
        children: items,
      )
    ];
  }

  List<Widget> _getDataSection() {
    return [
      SettingsSection(
        label: appLocalizations.dataSection,
        dividerIndentWithIcon: true,
        children: [_buildBackupItem()],
      )
    ];
  }

  List<Widget> _getOtherSection() {
    return [
      SettingsSection(
        label: appLocalizations.other,
        dividerIndentWithIcon: true,
        children: [
          ListItem.open(
            iconData: Icons.call_split,
            title: const Text('按应用分流'),
            subtitle: const Text('生成 PROCESS-NAME 规则'),
            delegate: const OpenDelegate(
              title: '按应用分流',
              widget: AppRoutingFragment(),
            ),
          ),
          ListItem.open(
            iconData: Icons.troubleshoot,
            title: const Text('诊断工具'),
            subtitle: const Text('分流规则测试 / 核心内存'),
            delegate: const OpenDelegate(
              title: '诊断工具',
              widget: DiagnosticsFragment(),
            ),
          ),
          ListItem.open(
            iconData: Icons.info_outline,
            title: Text(appLocalizations.about),
            valueText: globalState.packageInfo.version,
            delegate: OpenDelegate(
              title: appLocalizations.about,
              widget: const AboutFragment(),
            ),
          ),
          ListItem(
            iconData: Icons.gavel_outlined,
            title: Text(appLocalizations.disclaimer),
            onTap: () async {
              final isDisclaimerAccepted =
                  await globalState.appController.showDisclaimer();
              if (!isDisclaimerAccepted) {
                globalState.appController.handleExit();
              }
            },
          ),
        ],
      )
    ];
  }

  @override
  Widget build(BuildContext context) {
    return LocaleBuilder(
      builder: (_) {
        final items = [
          ..._getAppearanceSection(),
          ..._getConnectionSection(),
          ..._getSystemSection(),
          ..._getDataSection(),
          Selector<AppState, MoreToolsSelectorState>(
            selector: (_, appState) {
              return MoreToolsSelectorState(
                navigationItems: appState.viewMode == ViewMode.mobile
                    ? appState.navigationItems.where(
                        (element) {
                          return element.modes
                              .contains(NavigationItemMode.more);
                        },
                      ).toList()
                    : [],
              );
            },
            builder: (_, state, __) {
              if (state.navigationItems.isEmpty) {
                return Container();
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsSectionHeader(label: appLocalizations.more),
                  _buildNavigationMenu(state.navigationItems),
                ],
              );
            },
          ),
          ..._getOtherSection(),
          const SettingsBottomSpace(),
        ];
        return ValueListenableBuilder<double>(
          valueListenable: globalState.bottomBarHeightNotifier,
          builder: (_, bottomBarHeight, __) => ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, index) => items[index],
            // Extra scroll headroom equal to the floating bottom bar height
            // (mobile only) so the last item can scroll fully above it.
            padding: EdgeInsets.only(
              top: 4,
              bottom: 20 +
                  (MediaQuery.sizeOf(context).width <= maxMobileWidth
                      ? bottomBarHeight
                      : 0),
            ),
          ),
        );
      },
    );
  }
}
