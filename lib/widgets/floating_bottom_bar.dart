import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class FloatingBottomBar extends StatelessWidget {
  final List<NavigationItem> navigationItems;
  final int currentIndex;
  final ValueChanged<int> onTabChange;

  const FloatingBottomBar({
    super.key,
    required this.navigationItems,
    required this.currentIndex,
    required this.onTabChange,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: commonFilter,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 20,
                      color: Colors.black.withValues(alpha: 0.1),
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 15.0, vertical: 10),
                  child: GNav(
                    rippleColor: context.colorScheme.onSurface
                        .withValues(alpha: 0.1),
                    hoverColor: context.colorScheme.onSurface
                        .withValues(alpha: 0.05),
                    gap: 8,
                    activeColor: context.colorScheme.onSecondaryContainer,
                    iconSize: 24,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    duration: const Duration(milliseconds: 250),
                    tabBackgroundColor:
                        context.colorScheme.secondaryContainer,
                    color: context.colorScheme.onSurfaceVariant,
                    curve: Curves.easeInOut,
                    tabs: navigationItems
                        .map(
                          (e) => GButton(
                            icon: e.icon.icon ?? Icons.home,
                            text: Intl.message(e.label),
                          ),
                        )
                        .toList(),
                    selectedIndex: currentIndex,
                    onTabChange: onTabChange,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
