import 'package:fl_clash/widgets/list.dart';
import 'package:fl_clash/widgets/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归：设置卡片内的行必须保留显式声明的 trailing。
///
/// ListItem 的普通构造走 build() 里的兜底分支（只传 onTap），如果这一分支
/// 不回退到 widget.trailing，「编辑 / 上传 / 绑定」这类行尾按钮会整个消失。
void main() {
  testWidgets('plain ListItem keeps its trailing inside a card',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              SettingsSection(
                label: '文件',
                children: [
                  ListItem(
                    iconData: Icons.description_outlined,
                    title: const Text('配置'),
                    subtitle: const Text('5.37 KB · 1 分钟前'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'edit',
                          onPressed: () {},
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'upload',
                          onPressed: () {},
                          icon: const Icon(Icons.upload_outlined),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.upload_outlined), findsOneWidget);
  });

  testWidgets('block without caption is vertically symmetric', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsCard(
            children: [
              SettingsSubBlock(
                child: SettingsChips(
                  children: [
                    SettingsChoiceChip(label: '系统字体', isSelected: true),
                    const SettingsChoiceChip(label: 'MiSans'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final block = tester.widget<SettingsSubBlock>(
      find.byType(SettingsSubBlock),
    );
    expect(block.caption, isNull);

    // 无 caption 时上下留白应近似相等，控件不再贴卡片上沿。
    final padding = tester
        .widgetList<Padding>(
          find.descendant(
            of: find.byType(SettingsSubBlock),
            matching: find.byType(Padding),
          ),
        )
        .map((item) => item.padding)
        .whereType<EdgeInsets>()
        .firstWhere((item) => item.left == 16);
    expect(padding.top, greaterThanOrEqualTo(10));
    expect((padding.top - padding.bottom).abs(), lessThanOrEqualTo(4));
  });
}