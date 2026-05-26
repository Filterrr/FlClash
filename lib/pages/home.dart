import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

typedef OnSelected = void Function(int index);

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BackScope(
      child: Selector2<AppState, Config, HomeState>(
        selector: (_, appState, config) {
          return HomeState(
            currentLabel: appState.currentLabel,
            navigationItems: appState.currentNavigationItems,
            viewMode: appState.viewMode,
            locale: config.appSetting.locale,
          );
        },
        shouldRebuild: (prev, next) {
          return prev != next;
        },
        builder: (_, state, child) {
          final viewMode = state.viewMode;
          final navigationItems = state.navigationItems;
          final currentLabel = state.currentLabel;
          final index = navigationItems.lastIndexWhere(
            (element) => element.label == currentLabel,
          );
          final currentIndex = index == -1 ? 0 : index;
          final isMobile = viewMode == ViewMode.mobile;

          final bottomNavigationBar = _CustomNavigationBar(
            items: navigationItems,
            selectedIndex: currentIndex,
            onDestinationSelected: globalState.appController.toPage,
          );

          if (isMobile) {
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness:
                    Theme.of(context).brightness == Brightness.dark
                        ? Brightness.light
                        : Brightness.dark,
                systemNavigationBarColor:
                    context.colorScheme.surfaceContainer,
                systemNavigationBarDividerColor: Colors.transparent,
              ),
              child: Column(
                children: [
                  Flexible(
                    flex: 1,
                    child: MediaQuery.removePadding(
                      removeTop: false,
                      removeBottom: true,
                      removeLeft: true,
                      removeRight: true,
                      context: context,
                      child: CommonScaffold(
                        key: globalState.homeScaffoldKey,
                        title: Intl.message(currentLabel),
                        body: child!,
                      ),
                    ),
                  ),
                  MediaQuery.removePadding(
                    removeTop: true,
                    removeBottom: false,
                    removeLeft: true,
                    removeRight: true,
                    context: context,
                    child: bottomNavigationBar,
                  ),
                ],
              ),
            );
          } else {
            return AppSidebarContainer(
              navigationItems: navigationItems,
              currentIndex: currentIndex,
              onDestinationSelected: globalState.appController.toPage,
              child: CommonScaffold(
                key: globalState.homeScaffoldKey,
                title: Intl.message(currentLabel),
                body: child!,
              ),
            );
          }
        },
        child: _HomePageView(),
      ),
    );
  }
}

class _HomePageView extends StatefulWidget {
  const _HomePageView();

  @override
  State<_HomePageView> createState() => _HomePageViewState();
}

class _HomePageViewState extends State<_HomePageView> {
  List<NavigationItem> _navigationItems = [];

  _updatePageController(List<NavigationItem> navigationItems) {
    final currentLabel = globalState.appController.appState.currentLabel;
    final index = navigationItems.lastIndexWhere(
      (element) => element.label == currentLabel,
    );
    final currentIndex = index == -1 ? 0 : index;
    if (globalState.pageController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        globalState.appController.toPage(currentIndex, hasAnimate: true);
      });
    } else {
      globalState.pageController = PageController(
        initialPage: currentIndex,
        keepPage: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, List<NavigationItem>>(
      selector: (_, appState) => appState.currentNavigationItems,
      shouldRebuild: (prev, next) {
        return prev.length != next.length;
      },
      builder: (_, navigationItems, __) {
        _updatePageController(navigationItems);
        _navigationItems = navigationItems;
        return PageView.builder(
          controller: globalState.pageController,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: navigationItems.length,
          itemBuilder: (_, index) {
            final navigationItem = navigationItems[index];
            return KeepScope(
              keep: navigationItem.keep,
              key: Key(navigationItem.label),
              child: navigationItem.fragment,
            );
          },
        );
      },
    );
  }
}

class _CustomNavigationBar extends StatelessWidget {
  final List<NavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const _CustomNavigationBar({
    required this.items,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 80.0,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, -1),
            blurRadius: 3,
          ),
        ],
      ),
      child: Row(
        children: List.generate(items.length, (index) {
          return _CustomNavigationItem(
            icon: items[index].icon,
            label: Intl.message(items[index].label),
            isSelected: index == selectedIndex,
            colorScheme: colorScheme,
            onTap: () => onDestinationSelected(index),
          );
        }),
      ),
    );
  }
}

class _CustomNavigationItem extends StatelessWidget {
  final Icon icon;
  final String label;
  final bool isSelected;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _CustomNavigationItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubicEmphasized,
              padding: EdgeInsets.symmetric(
                horizontal: isSelected ? 16.0 : 0.0,
                vertical: isSelected ? 4.0 : 0.0,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.secondaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(100.0),
              ),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOutCubicEmphasized,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    IconTheme(
                      data: IconThemeData(
                        size: 24.0,
                        color: isSelected
                            ? colorScheme.onSecondaryContainer
                            : colorScheme.onSurfaceVariant,
                      ),
                      child: icon,
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SizeTransition(
                            sizeFactor: animation,
                            axis: Axis.horizontal,
                            axisAlignment: -1.0,
                            child: child,
                          ),
                        );
                      },
                      child: isSelected
                          ? Padding(
                              key: ValueKey(label),
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 14.0,
                                  height: 1.0,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSecondaryContainer,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          : const SizedBox.shrink(key: ValueKey('empty')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
