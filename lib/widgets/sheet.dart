import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/builder.dart';
import 'package:fl_clash/widgets/scaffold.dart';
import 'package:flutter/material.dart';

import 'side_sheet.dart';

Future<T?> showExtendBottomSheet<T>(
  BuildContext context, {
  required Widget body,
  required String title,
  String? activeLabel,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final screenHeight = MediaQuery.of(context).size.height;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(24),
      ),
    ),
    builder: (context) {
      Widget child = ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: screenHeight * 0.85,
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(24),
          ),
          child: CommonScaffold(
            transparentBackground: true,
            title: title,
            body: body,
            automaticallyImplyLeading: false,
            leading: SizedBox(
              height: kToolbarHeight,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ),
      );
      if (activeLabel != null) {
        child = BottomSheetActiveScope(
          activeLabel: activeLabel,
          child: child,
        );
      }
      return child;
    },
  );
}

showExtendPage(
  BuildContext context, {
  required Widget body,
  required String title,
  double? extendPageWidth,
  bool isScaffold = false,
  bool isBlur = true,
  Widget? action,
}) {
  final NavigatorState navigator = Navigator.of(context);
  final globalKey = GlobalKey();
  final uniqueBody = Container(
    key: globalKey,
    child: body,
  );
  final isMobile =
      globalState.appController.appState.viewMode == ViewMode.mobile;
  if (isMobile) {
    showExtendBottomSheet(
      context,
      body: uniqueBody,
      title: title,
    );
    return;
  }
  final isNotSide = isMobile || isScaffold;
  navigator.push(
    ModalSideSheetRoute(
      modalBarrierColor: Colors.black38,
      builder: (context) {
        final commonScaffold = CommonScaffold(
          automaticallyImplyLeading: isNotSide,
          actions: isNotSide
              ? null
              : [
                  const SizedBox(
                    height: kToolbarHeight,
                    width: kToolbarHeight,
                    child: CloseButton(),
                  ),
                ],
          title: title,
          body: uniqueBody,
        );
        return SizedBox(
          width: isMobile ? context.viewWidth : extendPageWidth ?? 300,
          child: commonScaffold,
        );
      },
      constraints: const BoxConstraints(),
      filter: isBlur ? commonFilter : null,
    ),
  );
}

showSheet({
  required BuildContext context,
  required WidgetBuilder builder,
  required String title,
  bool isScrollControlled = true,
  double width = 320,
}) {
  final viewMode = globalState.appController.appState.viewMode;
  final isMobile = viewMode == ViewMode.mobile;
  if (isMobile) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: builder(
            context,
          ),
        );
      },
      showDragHandle: true,
      useSafeArea: true,
    );
  } else {
    showModalSideSheet(
      useSafeArea: true,
      isScrollControlled: isScrollControlled,
      context: context,
      constraints: BoxConstraints(
        maxWidth: width,
      ),
      body: SafeArea(
        child: builder(context),
      ),
      title: title,
    );
  }
}
