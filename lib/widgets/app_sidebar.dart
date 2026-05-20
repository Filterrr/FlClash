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
              const ClipRect(child: AppIcon()),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: Selector<Config, bool>(
                selector: (_, config) => config.appSetting.showLabel,
                builder: (_, showLabel, __) {
                  return ScrollConfiguration(
                    behavior: _HiddenBarScrollBehavior(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: NavigationRail(
                            scrollable: true,
                            minExtendedWidth: 200,
                            backgroundColor: Colors.transparent,
                            selectedLabelTextStyle: context
                                .textTheme
                                .labelLarge!
                                .copyWith(
                                    color: context.colorScheme.onSurface),
                            unselectedLabelTextStyle: context
                                .textTheme
                                .labelLarge!
                                .copyWith(
                                    color: context.colorScheme.onSurface),
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
                            labelType: showLabel
                                ? NavigationRailLabelType.all
                                : NavigationRailLabelType.none,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            IconButton(
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
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class AppIcon extends StatelessWidget {
  const AppIcon({super.key});

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

class _HiddenBarScrollBehavior extends MaterialScrollBehavior {
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
