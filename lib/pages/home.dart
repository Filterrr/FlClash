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

          if (isMobile) {
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness:
                    Theme.of(context).brightness == Brightness.dark
                        ? Brightness.light
                        : Brightness.dark,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarDividerColor: Colors.transparent,
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 72),
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
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: FloatingBottomBar(
                      navigationItems: navigationItems,
                      currentIndex: currentIndex,
                      onTabChange: globalState.appController.toPage,
                    ),
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


