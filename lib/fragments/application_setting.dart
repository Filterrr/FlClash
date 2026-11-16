import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CloseConnectionsSwitch extends StatelessWidget {
  const CloseConnectionsSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<Config, bool>(
      selector: (_, config) => config.appSetting.closeConnections,
      builder: (_, closeConnections, __) {
        return ListItem.switchItem(
          isSettings: true,
          title: Text(appLocalizations.autoCloseConnections),
          subtitle: Text(appLocalizations.autoCloseConnectionsDesc),
          delegate: SwitchDelegate(
            value: closeConnections,
            onChanged: (value) async {
              final config = globalState.appController.config;
              config.appSetting = config.appSetting.copyWith(
                closeConnections: value,
              );
            },
          ),
        );
      },
    );
  }
}

class UsageSwitch extends StatelessWidget {
  const UsageSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<Config, bool>(
      selector: (_, config) => config.appSetting.onlyProxy,
      builder: (_, onlyProxy, __) {
        return ListItem.switchItem(
          isSettings: true,
          title: Text(appLocalizations.onlyStatisticsProxy),
          subtitle: Text(appLocalizations.onlyStatisticsProxyDesc),
          delegate: SwitchDelegate(
            value: onlyProxy,
            onChanged: (bool value) async {
              final config = globalState.appController.config;
              config.appSetting = config.appSetting.copyWith(
                onlyProxy: value,
              );
            },
          ),
        );
      },
    );
  }
}

class ApplicationSettingFragment extends StatelessWidget {
  const ApplicationSettingFragment({super.key});

  Widget _buildSwitchItem({
    required Widget title,
    required Widget subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListItem.switchItem(
      isSettings: true,
      title: title,
      subtitle: subtitle,
      delegate: SwitchDelegate(
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildBackgroundOptimization() {
    return Selector<Config,
        ({bool enabled, BackgroundOptimizationLevel level})>(
      selector: (_, config) => (
        enabled: config.appSetting.backgroundOptimization,
        level: config.appSetting.backgroundOptimizationLevel,
      ),
      builder: (_, state, __) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListItem.switchItem(
              isSettings: true,
              title: Text(appLocalizations.backgroundOptimization),
              subtitle: Text(appLocalizations.backgroundOptimizationDesc),
              delegate: SwitchDelegate(
                value: state.enabled,
                onChanged: (bool value) {
                  final config = globalState.appController.config;
                  config.appSetting = config.appSetting.copyWith(
                    backgroundOptimization: value,
                    backgroundOptimizationLevel: value
                        ? BackgroundOptimizationLevel.balanced
                        : BackgroundOptimizationLevel.disabled,
                  );
                },
              ),
            ),
            SettingsSubBlock(
              caption: appLocalizations.backgroundOptimizationLevelDesc,
              child: SettingsSegmented<BackgroundOptimizationLevel>(
                options: BackgroundOptimizationLevel.values,
                value: state.enabled
                    ? state.level
                    : BackgroundOptimizationLevel.disabled,
                labelBuilder: (level) => switch (level) {
                  BackgroundOptimizationLevel.disabled =>
                    appLocalizations.backgroundOptimizationLevel_disabled,
                  BackgroundOptimizationLevel.light =>
                    appLocalizations.backgroundOptimizationLevel_light,
                  BackgroundOptimizationLevel.balanced =>
                    appLocalizations.backgroundOptimizationLevel_balanced,
                  BackgroundOptimizationLevel.aggressive =>
                    appLocalizations.backgroundOptimizationLevel_aggressive,
                },
                onChanged: (BackgroundOptimizationLevel value) {
                  final config = globalState.appController.config;
                  config.appSetting = config.appSetting.copyWith(
                    backgroundOptimizationLevel: value,
                    backgroundOptimization:
                        value != BackgroundOptimizationLevel.disabled,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 4),
      children: [
        SettingsSection(
          label: appLocalizations.startupSection,
          children: [
            Selector<Config, bool>(
              selector: (_, config) => config.appSetting.autoRun,
              builder: (_, autoRun, __) => _buildSwitchItem(
                title: Text(appLocalizations.autoRun),
                subtitle: Text(appLocalizations.autoRunDesc),
                value: autoRun,
                onChanged: (bool value) {
                  final config = globalState.appController.config;
                  config.appSetting = config.appSetting.copyWith(
                    autoRun: value,
                  );
                },
              ),
            ),
            Selector<Config, bool>(
              selector: (_, config) => config.appSetting.minimizeOnExit,
              builder: (_, minimizeOnExit, __) => _buildSwitchItem(
                title: Text(appLocalizations.minimizeOnExit),
                subtitle: Text(appLocalizations.minimizeOnExitDesc),
                value: minimizeOnExit,
                onChanged: (bool value) {
                  final config = context.read<Config>();
                  config.appSetting = config.appSetting.copyWith(
                    minimizeOnExit: value,
                  );
                },
              ),
            ),
            if (system.isDesktop)
              Selector<Config, bool>(
                selector: (_, config) => config.appSetting.autoLaunch,
                builder: (_, autoLaunch, __) => _buildSwitchItem(
                  title: Text(appLocalizations.autoLaunch),
                  subtitle: Text(appLocalizations.autoLaunchDesc),
                  value: autoLaunch,
                  onChanged: (bool value) {
                    final config = globalState.appController.config;
                    config.appSetting = config.appSetting.copyWith(
                      autoLaunch: value,
                    );
                  },
                ),
              ),
            if (system.isDesktop)
              Selector<Config, bool>(
                selector: (_, config) => config.appSetting.silentLaunch,
                builder: (_, silentLaunch, __) => _buildSwitchItem(
                  title: Text(appLocalizations.silentLaunch),
                  subtitle: Text(appLocalizations.silentLaunchDesc),
                  value: silentLaunch,
                  onChanged: (bool value) {
                    final config = globalState.appController.config;
                    config.appSetting = config.appSetting.copyWith(
                      silentLaunch: value,
                    );
                  },
                ),
              ),
          ],
        ),
        SettingsSection(
          label: appLocalizations.backgroundSection,
          children: [
            _buildBackgroundOptimization(),
            if (Platform.isAndroid)
              Selector<Config, bool>(
                selector: (_, config) => config.appSetting.hidden,
                builder: (_, isExclude, __) => _buildSwitchItem(
                  title: Text(appLocalizations.exclude),
                  subtitle: Text(appLocalizations.excludeDesc),
                  value: isExclude,
                  onChanged: (value) {
                    final config = globalState.appController.config;
                    config.appSetting = config.appSetting.copyWith(
                      hidden: value,
                    );
                  },
                ),
              ),
          ],
        ),
        SettingsSection(
          label: appLocalizations.interfaceSection,
          children: [
            if (Platform.isAndroid)
              Selector<Config, bool>(
                selector: (_, config) => config.appSetting.isAnimateToPage,
                builder: (_, isAnimateToPage, __) => _buildSwitchItem(
                  title: Text(appLocalizations.tabAnimation),
                  subtitle: Text(appLocalizations.tabAnimationDesc),
                  value: isAnimateToPage,
                  onChanged: (value) {
                    final config = globalState.appController.config;
                    config.appSetting = config.appSetting.copyWith(
                      isAnimateToPage: value,
                    );
                  },
                ),
              ),
            Selector<Config, bool>(
              selector: (_, config) => config.appSetting.openLogs,
              builder: (_, openLogs, __) => _buildSwitchItem(
                title: Text(appLocalizations.logcat),
                subtitle: Text(appLocalizations.logcatDesc),
                value: openLogs,
                onChanged: (bool value) {
                  final config = globalState.appController.config;
                  config.appSetting = config.appSetting.copyWith(
                    openLogs: value,
                  );
                },
              ),
            ),
          ],
        ),
        SettingsSection(
          label: appLocalizations.behaviorSection,
          children: [
            const CloseConnectionsSwitch(),
            const UsageSwitch(),
          ],
        ),
        SettingsSection(
          label: appLocalizations.update,
          children: [
            Selector<Config, bool>(
              selector: (_, config) => config.appSetting.autoCheckUpdate,
              builder: (_, autoCheckUpdate, __) => _buildSwitchItem(
                title: Text(appLocalizations.autoCheckUpdate),
                subtitle: Text(appLocalizations.autoCheckUpdateDesc),
                value: autoCheckUpdate,
                onChanged: (bool value) {
                  final config = globalState.appController.config;
                  config.appSetting = config.appSetting.copyWith(
                    autoCheckUpdate: value,
                  );
                },
              ),
            ),
          ],
        ),
        SettingsNote(
          text: appLocalizations.settingsPlatformTip,
        ),
        const SettingsBottomSpace(),
      ],
    );
  }
}
