import 'package:fl_clash/widgets/list.dart';
import 'package:fl_clash/widgets/open_container.dart';
import 'package:fl_clash/widgets/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归：设置卡片内的行不能自带不透明底色。
///
/// OpenContainer 在关闭态会包一层 Material；如果这一层沿用 Material 的默认
/// 底色（canvasColor，不透明），就会把外层卡片的底色整块盖住，同一个卡片里
/// 出现两种底色、圆角看起来错位。这里锁定该材质必须是透明的。
void main() {
  Widget buildCard() {
    return MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            SettingsSection(
              label: '外观',
              children: [
                ListItem.open(
                  iconData: Icons.palette_outlined,
                  title: const Text('主题'),
                  subtitle: const Text('设置深色模式，调整色彩'),
                  valueText: '自动',
                  delegate: OpenDelegate(
                    title: '主题',
                    widget: const SizedBox(),
                  ),
                ),
                ListItem<Locale?>.options(
                  iconData: Icons.language_outlined,
                  title: const Text('语言'),
                  valueText: '默认',
                  delegate: OptionsDelegate<Locale?>(
                    title: '语言',
                    options: const <Locale?>[null],
                    value: null,
                    textBuilder: (_) => '默认',
                    onChanged: (_) {},
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('card rows do not paint an opaque layer over the card',
      (tester) async {
    await tester.pumpWidget(buildCard());

    // OpenContainer 带泛型参数，byType 会因实例化类型不同而匹配不到，
    // 这里用谓词匹配。
    final openContainers = find.byWidgetPredicate(
      (widget) => widget is OpenContainer,
    );
    expect(openContainers, findsOneWidget);

    final rowMaterials = tester.widgetList<Material>(
      find.descendant(
        of: openContainers,
        matching: find.byType(Material),
      ),
    );
    expect(rowMaterials, isNotEmpty);
    for (final material in rowMaterials) {
      expect(
        material.color,
        Colors.transparent,
        reason: 'OpenContainer 关闭态必须透明，否则会盖住分组卡片底色',
      );
    }
  });

  testWidgets('card background is painted once behind its rows', (tester) async {
    await tester.pumpWidget(buildCard());

    // 卡片外层由带圆角的 Material 承载底色；行内的 Material 必须透明。
    final cardMaterials = tester
        .widgetList<Material>(
          find.ancestor(
            of: find.text('主题'),
            matching: find.byType(Material),
          ),
        )
        .where((material) => material.shape is RoundedRectangleBorder)
        .toList();
    expect(cardMaterials, isNotEmpty, reason: '分组卡片必须由 Material 承载');
    expect(
      cardMaterials.first.color?.a,
      greaterThan(0.5),
      reason: '卡片底色必须不透明',
    );
  });
}