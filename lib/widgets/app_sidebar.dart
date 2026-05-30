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
                  child: ScrollConfiguration(
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
                                    icon: Tooltip(
                                      message: Intl.message(e.label),
                                      child: e.icon,
                                    ),
                                    label: Text(Intl.message(e.label)),
                                  ),
                                )
                                .toList(),
                            onDestinationSelected: onDestinationSelected,
                            extended: false,
                            selectedIndex: currentIndex,
                            labelType: NavigationRailLabelType.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 12, endIndent: 12),
                Selector<Config, bool>(
                  selector: (_, config) => config.networkProps.systemProxy,
                  builder: (_, systemProxy, __) {
                    return _SidebarQuickIcon(
                      icon: Icons.shuffle,
                      tooltip: appLocalizations.systemProxy,
                      isActive: systemProxy,
                      onPressed: () {
                        final config = globalState.appController.config;
                        config.networkProps =
                            config.networkProps.copyWith(systemProxy: !systemProxy);
                      },
                    );
                  },
                ),
                Selector<ClashConfig, bool>(
                  selector: (_, clashConfig) => clashConfig.tun.enable,
                  builder: (_, tunEnable, __) {
                    return _SidebarQuickIcon(
                      icon: Icons.stacked_line_chart,
                      tooltip: appLocalizations.tun,
                      isActive: tunEnable,
                      onPressed: () {
                        final clashConfig = globalState.appController.clashConfig;
                        clashConfig.tun =
                            clashConfig.tun.copyWith(enable: !tunEnable);
                      },
                    );
                  },
                ),
                const SizedBox(height: 72),
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

class _SidebarQuickIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onPressed;

  const _SidebarQuickIcon({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = context.colorScheme.primary;
    final inactiveColor = context.colorScheme.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: isActive ? activeColor : inactiveColor,
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
