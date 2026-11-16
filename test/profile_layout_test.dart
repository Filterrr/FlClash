import 'package:fl_clash/fragments/profiles/profiles.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/widgets/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归：配置卡片的徽标布局与排序弹层的高度。
///
/// 1. 摘要卡头行的类型徽标曾被 Spacer 推到卡片最右边，和左侧「当前配置」
///    隔着整卡宽度；现在它必须紧跟标签。
/// 2. 配置卡里的徽标与 ⋮ 菜单、名称挤在同一行时，徽标要贴着菜单而不是浮在
///    文字中间。
/// 3. 排序弹层沿用原始实现（CommonCard.filled + ListTile），本次不做断言。
void main() {
  setUpAll(() async {
    await AppLocalizations.load(const Locale('en'));
  });

  Profile buildProfile({String id = 'p1', String? label = 'Airport Pro'}) {
    return Profile(
      id: id,
      label: label,
      url: 'https://sub.example.com/api',
      autoUpdateDuration: const Duration(minutes: 1440),
    );
  }

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => child),
      ),
    );
  }

  testWidgets('profile card keeps badge next to the menu', (tester) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 360,
          child: ProfileItem(
            profile: buildProfile(),
            // 非当前项才会显示类型徽标；当前项显示「当前」。
            groupValue: null,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final badge = find.text('URL');
    expect(badge, findsOneWidget);

    final badgeRect = tester.getRect(badge);
    final cardRect = tester.getRect(
      find.byType(SettingsIconTile),
    );
    expect(
      badgeRect.right,
      greaterThan(cardRect.right + 100),
      reason: '徽标应贴在卡片右侧，而不是浮在名称文字中间',
    );
  });

  testWidgets('badge and menu share one vertical centre line', (tester) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 360,
          child: ProfileItem(
            profile: buildProfile(),
            groupValue: null,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final badgeRect = tester.getRect(find.text('URL'));
    final menuRect = tester.getRect(find.byIcon(Icons.more_vert));

    expect(
      (badgeRect.center.dy - menuRect.center.dy).abs(),
      lessThan(3),
      reason: '徽标与 ⋮ 必须共用同一条垂直中线',
    );
  });
}
