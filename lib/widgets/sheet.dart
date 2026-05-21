import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/scaffold.dart';
import 'package:flutter/material.dart';

import 'side_sheet.dart';

showExtendBottomSheet(
  BuildContext context, {
  required Widget body,
  required String title,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final screenHeight = MediaQuery.of(context).size.height;
  showModalBottomSheet(
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
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: screenHeight * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: 4,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: body,
            ),
          ],
        ),
      );
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
