import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class AppSidebar extends StatelessWidget {
  final List<NavigationItem> navigationItems;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  const AppSidebar({
    super.key,
    required this.navigationItems,
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colorScheme.surfaceContainer,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (Platform.isMacOS) const SizedBox(height: 22),
            const SizedBox(height: 10),
            if (!Platform.isMacOS) ...[
              const ClipRect(child: _SidebarAppIcon()),
              const SizedBox(height: 4),
              _SidebarVersionLabel(),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: Selector<Config, bool>(
                selector: (_, config) => config.appSetting.showLabel,
                builder: (_, showLabel, __) {
                  return _SidebarNavigationRail(
                    navigationItems: navigationItems,
                    currentIndex: currentIndex,
                    onDestinationSelected: onDestinationSelected,
                    showLabel: showLabel,
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            if (system.isDesktop) const _SidebarQuickToggles(),
            if (system.isDesktop) const SizedBox(height: 8),
            _SidebarToggleLabelButton(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _SidebarAppIcon extends StatelessWidget {
  const _SidebarAppIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: ShapeDecoration(
        color: context.colorScheme.surfaceContainerHighest,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Transform.translate(
        offset: const Offset(0, -1),
        child: Image.asset(
          'assets/images/icon.png',
          width: 34,
          height: 34,
        ),
      ),
    );
  }
}

class _SidebarVersionLabel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final version = globalState.packageInfo.version;
    return Text(
      'v$version',
      style: context.textTheme.labelSmall?.copyWith(
        color: context.colorScheme.onSurfaceVariant.opacity60,
      ),
    );
  }
}

class _SidebarNavigationRail extends StatelessWidget {
  final List<NavigationItem> navigationItems;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool showLabel;

  const _SidebarNavigationRail({
    required this.navigationItems,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.showLabel,
  });

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      scrollable: true,
      minExtendedWidth: 200,
      backgroundColor: Colors.transparent,
      selectedLabelTextStyle: context.textTheme.labelLarge?.copyWith(
        color: context.colorScheme.onSurface,
      ),
      unselectedLabelTextStyle: context.textTheme.labelLarge?.copyWith(
        color: context.colorScheme.onSurface,
      ),
      destinations: navigationItems
          .map(
            (e) => NavigationRailDestination(
              icon: e.icon,
              label: Text(Intl.message(e.label)),
            ),
          )
          .toList(),
      onDestinationSelected: onDestinationSelected,
      extended: false,
      selectedIndex: currentIndex,
      labelType:
          showLabel ? NavigationRailLabelType.all : NavigationRailLabelType.none,
    );
  }
}

class _SidebarQuickToggles extends StatelessWidget {
  const _SidebarQuickToggles();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SystemProxyToggle(),
        const SizedBox(height: 4),
        _TunToggle(),
      ],
    );
  }
}

class _SystemProxyToggle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isActive = context.select<Config, bool>(
      (config) => config.networkProps.systemProxy,
    );
    return _SidebarToggleChip(
      icon: Icons.shuffle,
      isActive: isActive,
      onTap: () {
        final config = globalState.appController.config;
        config.networkProps =
            config.networkProps.copyWith(systemProxy: !isActive);
      },
    );
  }
}

class _TunToggle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isActive = context.select<ClashConfig, bool>(
      (clashConfig) => clashConfig.tun.enable,
    );
    return _SidebarToggleChip(
      icon: Icons.stacked_line_chart,
      isActive: isActive,
      onTap: () {
        final clashConfig = globalState.appController.clashConfig;
        clashConfig.tun = clashConfig.tun.copyWith(enable: !isActive);
      },
    );
  }
}

class _SidebarToggleChip extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _SidebarToggleChip({
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 32,
      child: Material(
        color: isActive
            ? context.colorScheme.secondaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Icon(
            icon,
            size: 20,
            color: isActive
                ? context.colorScheme.onSecondaryContainer
                : context.colorScheme.onSurfaceVariant.opacity38,
          ),
        ),
      ),
    );
  }
}

class _SidebarToggleLabelButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {
        final config = globalState.appController.config;
        final appSetting = config.appSetting;
        config.appSetting = appSetting.copyWith(
          showLabel: !appSetting.showLabel,
        );
      },
      icon: Icon(
        Icons.menu,
        color: context.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
