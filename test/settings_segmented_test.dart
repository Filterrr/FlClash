import 'package:fl_clash/widgets/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归：优化级别等分段控件点击后，选中滑块要左右滑动过去，
/// 而不是「每段各自淡入一块底色」。
void main() {
  testWidgets('segmented thumb slides to the tapped segment', (tester) async {
    var selected = 0;
    const labels = ['关闭', '轻量', '均衡', '激进'];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: StatefulBuilder(
                builder: (context, setState) => SettingsSegmented<int>(
                  options: const [0, 1, 2, 3],
                  value: selected,
                  labelBuilder: (index) => labels[index],
                  onChanged: (index) {
                    setState(() {
                      selected = index;
                    });
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final thumb = find.byType(AnimatedPositioned);
    expect(thumb, findsOneWidget);

    // 初始选中第 0 段：滑块贴在左侧。
    expect(tester.widget<AnimatedPositioned>(thumb).left, 0);

    await tester.tap(find.text('均衡'));
    await tester.pumpAndSettle();

    expect(selected, 2);

    // 320 宽减去左右各 3 的内衬 = 314，四等分后每段 78.5。
    expect(
      tester.widget<AnimatedPositioned>(thumb).left,
      closeTo(78.5 * 2, 0.6),
      reason: '滑块应移动到第三段的起始位置',
    );

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    expect(selected, 0);
    expect(tester.widget<AnimatedPositioned>(thumb).left, 0);
  });

  testWidgets('segmented control only animates one thumb at a time',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: SettingsSegmented<int>(
                options: const [0, 1, 2],
                value: 1,
                labelBuilder: (index) => '选项$index',
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    // 只有一个滑动块；旧实现是每段各有一个 AnimatedContainer。
    expect(find.byType(AnimatedPositioned), findsOneWidget);
    expect(
      tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned)).left,
      closeTo((240 - 6) / 3, 0.6),
    );
  });
}
