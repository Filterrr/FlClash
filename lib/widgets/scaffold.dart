import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CommonScaffold extends StatefulWidget {
  final Widget body;
  final String title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool automaticallyImplyLeading;

  const CommonScaffold({
    super.key,
    required this.body,
    this.leading,
    required this.title,
    this.actions,
    this.automaticallyImplyLeading = true,
  });

  CommonScaffold.open({
    Key? key,
    required Widget body,
    required String title,
    required Function onBack,
  }) : this(
          key: key,
          body: body,
          title: title,
          automaticallyImplyLeading: false,
          leading: SizedBox(
            height: kToolbarHeight,
            child: IconButton(
              icon: const BackButtonIcon(),
              onPressed: () {
                onBack();
              },
            ),
          ),
        );

  @override
  State<CommonScaffold> createState() => CommonScaffoldState();
}

class CommonScaffoldState extends State<CommonScaffold> {
  final ValueNotifier<List<Widget>> _actions = ValueNotifier([]);
  final ValueNotifier<dynamic> _floatingActionButton = ValueNotifier(null);
  final ValueNotifier<bool> _loading = ValueNotifier(false);

  set actions(List<Widget> actions) {
    if (_actions.value != actions) {
      _actions.value = actions;
    }
  }

  set floatingActionButton(Widget? floatingActionButton) {
    if (_floatingActionButton.value != floatingActionButton) {
      _floatingActionButton.value = floatingActionButton;
    }
  }

  Future<T?> loadingRun<T>(
    Future<T> Function() futureFunction, {
    String? title,
  }) async {
    _loading.value = true;
    try {
      final res = await futureFunction();
      _loading.value = false;
      return res;
    } catch (e) {
      globalState.showMessage(
        title: title ?? appLocalizations.tip,
        message: TextSpan(
          text: e.toString(),
        ),
      );
      _loading.value = false;
      return null;
    }
  }

  @override
  void dispose() {
    _actions.dispose();
    _floatingActionButton.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CommonScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title) {
      _actions.value = [];
      _floatingActionButton.value = null;
    }
  }

  Widget get body => SafeArea(child: widget.body);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _floatingActionButton,
      builder: (_, value, __) {
        // Listen to the real measured bottom bar height. When it changes, a
        // new [_FloatingBarAwareLocation] with a different value is produced,
        // so Scaffold detects a location change in didUpdateWidget and
        // re-runs the FAB layout. Without this, the framework's
        // _ScaffoldLayout.shouldRelayout never knows about the global
        // notifier and the FAB keeps its stale offset until the FAB is
        // removed and re-added (e.g. after switching tabs).
        return ValueListenableBuilder<double>(
          valueListenable: globalState.bottomBarHeightNotifier,
          builder: (context, bottomBarHeight, ___) {
            return Scaffold(
              resizeToAvoidBottomInset: true,
              floatingActionButtonLocation: _isMobile(context)
                  ? _FloatingBarAwareLocation(bottomBarHeight)
                  : null,
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(kToolbarHeight),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    ValueListenableBuilder<List<Widget>>(
                      valueListenable: _actions,
                      builder: (_, actions, __) {
                        final realActions =
                            actions.isNotEmpty ? actions : widget.actions;
                        return AppBar(
                          centerTitle: false,
                          systemOverlayStyle: SystemUiOverlayStyle(
                            statusBarColor: Colors.transparent,
                            statusBarIconBrightness:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Brightness.light
                                    : Brightness.dark,
                            systemNavigationBarIconBrightness:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Brightness.light
                                    : Brightness.dark,
                            systemNavigationBarColor:
                                context.colorScheme.surface,
                            systemNavigationBarDividerColor: Colors.transparent,
                          ),
                          automaticallyImplyLeading:
                              widget.automaticallyImplyLeading,
                          leading: widget.leading,
                          title: Text(widget.title),
                          actions: [
                            ...?realActions,
                            const SizedBox(
                              width: 8,
                            )
                          ],
                        );
                      },
                    ),
                    ValueListenableBuilder(
                      valueListenable: _loading,
                      builder: (_, value, __) {
                        return value == true
                            ? const LinearProgressIndicator()
                            : Container();
                      },
                    ),
                  ],
                ),
              ),
              body: body,
              floatingActionButton: value,
            );
          },
        );
      },
    );
  }
}

bool _isMobile(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return width <= maxMobileWidth;
}

class _FloatingBarAwareLocation extends FloatingActionButtonLocation {
  final double floatingBarHeight;

  /// A value-based location: a new instance is created whenever the measured
  /// bottom bar height changes, so that [Scaffold] detects the location change
  /// (via `==` in didUpdateWidget) and re-runs the FAB layout instead of
  /// keeping a stale offset. This fixes the FAB overlapping the floating
  /// bottom bar on devices whose nav bar height / font scale makes the bar
  /// taller than the notifier's 92.0 default, which previously persisted
  /// until the FAB got removed and re-added by a tab switch.
  const _FloatingBarAwareLocation(this.floatingBarHeight);

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final defaultOffset =
        FloatingActionButtonLocation.endFloat.getOffset(scaffoldGeometry);
    return Offset(
      defaultOffset.dx,
      defaultOffset.dy - floatingBarHeight,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _FloatingBarAwareLocation &&
          other.floatingBarHeight == floatingBarHeight;

  @override
  int get hashCode => floatingBarHeight.hashCode;
}
