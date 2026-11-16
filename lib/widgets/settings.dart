import 'package:flutter/material.dart';

import '../common/common.dart';

const settingsCardRadius = 18.0;
const settingsControlRadius = 12.0;
const settingsIconTileSize = 34.0;
const settingsRowIndent = 16.0;
const settingsCardMargin = EdgeInsets.symmetric(horizontal: 16);

/// 分组标题：11.5 / 650 / 字距 .8，右侧可回显当前值。
class SettingsSectionHeader extends StatelessWidget {
  final String label;
  final String? value;
  final EdgeInsets? padding;

  const SettingsSectionHeader({
    super.key,
    required this.label,
    this.value,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;
    return Padding(
      padding: padding ??
          const EdgeInsets.only(
            left: 22,
            right: 22,
            top: 18,
            bottom: 7,
          ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
          if (value != null)
            Text(
              value!,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// 卡片作用域：卡片内的 ListItem 自动切换为设置行样式。
class SettingsSectionScope extends InheritedWidget {
  final bool isCard;

  const SettingsSectionScope({
    super.key,
    required this.isCard,
    required super.child,
  });

  static bool of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<SettingsSectionScope>();
    return scope?.isCard ?? false;
  }

  @override
  bool updateShouldNotify(SettingsSectionScope oldWidget) {
    return isCard != oldWidget.isCard;
  }
}

/// 分组卡片：圆角 18、1px 描边、行间内缩分隔线。
class SettingsCard extends StatelessWidget {
  final List<Widget> children;
  final bool dividerIndentWithIcon;

  const SettingsCard({
    super.key,
    required this.children,
    this.dividerIndentWithIcon = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final visibleChildren = children.where((e) => e is! SizedBox).toList();
    final rows = <Widget>[];
    for (var index = 0; index < visibleChildren.length; index++) {
      if (index > 0) {
        rows.add(
          Divider(
            height: 1,
            thickness: 1,
            indent: dividerIndentWithIcon
                ? settingsRowIndentWithIcon
                : settingsRowIndent,
            endIndent: settingsRowIndent,
            color: colorScheme.outlineVariant.opacity60,
          ),
        );
      }
      rows.add(visibleChildren[index]);
    }
    return Padding(
      padding: settingsCardMargin,
      child: Material(
        color: colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(settingsCardRadius),
          side: BorderSide(
            color: colorScheme.outlineVariant.opacity60,
          ),
        ),
        child: SettingsSectionScope(
          isCard: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: rows,
          ),
        ),
      ),
    );
  }
}

const settingsRowIndentWithIcon = 62.0;

/// 只提供卡片背景与描边（用于可滚动列表，卡片本身不参与滚动）。
class SettingsCardSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsets margin;

  const SettingsCardSurface({
    super.key,
    required this.child,
    this.margin = settingsCardMargin,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: margin,
      child: Material(
        color: colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(settingsCardRadius),
          side: BorderSide(
            color: colorScheme.outlineVariant.opacity60,
          ),
        ),
        child: SettingsSectionScope(
          isCard: true,
          child: child,
        ),
      ),
    );
  }
}

/// 分组标题 + 卡片。
class SettingsSection extends StatelessWidget {
  final String label;
  final String? value;
  final List<Widget> children;
  final bool dividerIndentWithIcon;

  const SettingsSection({
    super.key,
    required this.label,
    this.value,
    required this.children,
    this.dividerIndentWithIcon = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(label: label, value: value),
        SettingsCard(
          dividerIndentWithIcon: dividerIndentWithIcon,
          children: children,
        ),
      ],
    );
  }
}

/// 图标底托：34×34、主色 11% 底色、圆角 11。
class SettingsIconTile extends StatelessWidget {
  final IconData iconData;
  final bool isNeutral;

  const SettingsIconTile({
    super.key,
    required this.iconData,
    this.isNeutral = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Container(
      width: settingsIconTileSize,
      height: settingsIconTileSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isNeutral
            ? colorScheme.surfaceContainerHighest
            : colorScheme.primary.opacity10,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(
        iconData,
        size: 18,
        color: isNeutral ? colorScheme.onSurfaceVariant : colorScheme.primary,
      ),
    );
  }
}

/// 导航行尾部的「当前值 + 箭头」。
class SettingsTrailing extends StatelessWidget {
  final String? value;
  final bool showChevron;

  const SettingsTrailing({
    super.key,
    this.value,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (value != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 132),
            child: Text(
              value!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: context.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (showChevron) ...[
          if (value != null)
            const SizedBox(
              width: 4,
            ),
          Icon(
            Icons.chevron_right,
            size: 18,
            color: colorScheme.outline,
          ),
        ],
      ],
    );
  }
}

/// 分段控件：内衬 3px + 圆角 12，选项与回调由调用方提供。
class SettingsSegmented<T> extends StatelessWidget {
  final List<T> options;
  final T value;
  final String Function(T value) labelBuilder;
  final IconData? Function(T value)? iconBuilder;
  final Function(T value) onChanged;

  const SettingsSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.labelBuilder,
    required this.onChanged,
    this.iconBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.opacity60,
        borderRadius: BorderRadius.circular(settingsControlRadius),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    onChanged(option);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: option == value
                          ? colorScheme.surfaceContainerLow
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9.5),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (iconBuilder?.call(option) != null) ...[
                          Icon(
                            iconBuilder!.call(option),
                            size: 14,
                            color: option == value
                                ? colorScheme.onSurface
                                : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(
                            width: 5,
                          ),
                        ],
                        Flexible(
                          child: Text(
                            labelBuilder(option),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: textTheme.bodySmall?.copyWith(
                              fontWeight: option == value
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: option == value
                                  ? colorScheme.onSurface
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 胶囊选择。
class SettingsChoiceChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final void Function()? onPressed;

  const SettingsChoiceChip({
    super.key,
    required this.label,
    this.isSelected = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Material(
      color: isSelected
          ? colorScheme.primary
          : colorScheme.surfaceContainerHighest.opacity60,
      borderRadius: BorderRadius.circular(settingsControlRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 7,
          ),
          child: Text(
            label,
            style: context.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: isSelected
                  ? colorScheme.onPrimary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// 卡片内的内嵌区块（分段控件、胶囊组、色板等）。
class SettingsSubBlock extends StatelessWidget {
  final Widget child;
  final String? caption;
  final String? captionValue;

  const SettingsSubBlock({
    super.key,
    required this.child,
    this.caption,
    this.captionValue,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    // 有 caption 时上方只需 2dp（caption 自带 8dp 下边距）；没有 caption 的
    // 纯控件区块若也用 2dp，胶囊/分段控件会贴着卡片上沿，视觉上下失衡。
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: caption == null ? 14 : 2,
        bottom: 14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (caption != null)
            Padding(
              padding: const EdgeInsets.only(
                left: 2,
                right: 2,
                bottom: 8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      caption!,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (captionValue != null)
                    Text(
                      captionValue!,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// 底部说明文字。
class SettingsNote extends StatelessWidget {
  final String text;
  final EdgeInsets? padding;

  const SettingsNote({
    super.key,
    required this.text,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    // 图标用 RichText 的 WidgetSpan 内联到首行，这样换行后每一行都从同一
    // 左边界开始；用 Row(Icon + Text) 会让第二行缩进到文字起点，看起来错位。
    final textTheme = context.textTheme;
    final style = textTheme.bodySmall?.copyWith(
      color: colorScheme.outline,
      height: 1.5,
    );
    return Padding(
      padding: padding ??
          const EdgeInsets.only(
            left: 22,
            right: 22,
            top: 8,
          ),
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.info_outline,
                  size: 13,
                  color: colorScheme.outline,
                ),
              ),
            ),
            TextSpan(text: text),
          ],
        ),
        style: style,
      ),
    );
  }
}

/// 胶囊组：换行排列。
class SettingsChips extends StatelessWidget {
  final List<Widget> children;

  const SettingsChips({
    super.key,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: children,
    );
  }
}

/// 主题色色块：44×44、圆角 14，选中加外环与勾。
class SettingsColorSwatch extends StatelessWidget {
  final Color seedColor;
  final bool isSelected;
  final Widget? overlayIcon;
  final void Function()? onPressed;

  const SettingsColorSwatch({
    super.key,
    required this.seedColor,
    this.isSelected = false,
    this.overlayIcon,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final previewScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Theme.of(context).brightness,
    );
    return GestureDetector(
      onTap: onPressed,
      child: SizedBox(
        width: 52,
        height: 52,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    previewScheme.primary,
                    previewScheme.primaryContainer,
                  ],
                ),
              ),
              child: Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  margin: const EdgeInsets.all(5),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: previewScheme.tertiary,
                  ),
                ),
              ),
            ),
            if (overlayIcon != null)
              IconTheme.merge(
                data: IconThemeData(
                  size: 16,
                  color: previewScheme.onPrimary,
                ),
                child: overlayIcon!,
              ),
            if (isSelected)
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(17.5),
                  border: Border.all(
                    color: colorScheme.primary,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.surfaceContainerLowest.opacity80,
                  ),
                  child: Icon(
                    Icons.check,
                    size: 15,
                    color: colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 页面底部留白。
class SettingsBottomSpace extends StatelessWidget {
  final double height;

  const SettingsBottomSpace({super.key, this.height = 32});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
    );
  }
}
