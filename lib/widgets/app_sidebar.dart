import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class AppSidebarContainer extends StatelessWidget {
  final Widget child;
  final List<NavigationItem> navigationItems;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  const AppSidebarContainer({
    super.key,
    required this.child,
    required this.navigationItems,
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  Widget _buildBackground({required BuildContext context, required Widget child}) {
    return Material(color: context.colorScheme.surfaceContainer, child: child);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _buildBackground(
          context: context,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (system.isMacOS) const SizedBox(height: 22),
                const SizedBox(height: 10),
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
                const Divider(height: 1, indent: 12, endIndent: 12),
                _SidebarQuickSwitch(
                  icon: Icons.shuffle,
                  label: appLocalizations.systemProxy,
                  selector: Selector<Config, bool>(
                    selector: (_, config) => config.networkProps.systemProxy,
                    builder: (_, value, __) {
                      return Switch(
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        value: value,
                        onChanged: (v) {
                          final config = globalState.appController.config;
                          config.networkProps =
                              config.networkProps.copyWith(systemProxy: v);
                        },
                      );
                    },
                  ),
                ),
                _SidebarQuickSwitch(
                  icon: Icons.stacked_line_chart,
                  label: appLocalizations.tun,
                  selector: Selector<ClashConfig, bool>(
                    selector: (_, clashConfig) => clashConfig.tun.enable,
                    builder: (_, value, __) {
                      return Switch(
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        value: value,
                        onChanged: (v) {
                          final clashConfig =
                              globalState.appController.clashConfig;
                          clashConfig.tun =
                              clashConfig.tun.copyWith(enable: v);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
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
        ),
        Expanded(
          flex: 1,
          child: ClipRect(child: child),
        ),
      ],
    );
  }
}

class _SidebarQuickSwitch extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget selector;

  const _SidebarQuickSwitch({
    required this.icon,
    required this.label,
    required this.selector,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: context.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: context.textTheme.labelSmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          selector,
        ],
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
