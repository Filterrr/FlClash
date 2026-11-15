import 'package:fl_clash/fragments/profiles/profiles.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/widgets/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归：配置卡片必须是一整块不透明卡片，且当前配置有独立标记。
void main() {
  const profile = Profile(
    id: 'p1',
    label: 'Airport Pro',
    url: 'https://sub.example.com/api',
    autoUpdateDuration: Duration(minutes: 1440),
    subscriptionInfo: SubscriptionInfo(
      upload: 1024,
      download: 2048,
      total: 10240,
      expire: 0,
    ),
  );

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => child),
      ),
    );
  }

  testWidgets('profile card paints an opaque background', (tester) async {
    await tester.pumpWidget(
      wrap(
        ProfileItem(
          profile: profile,
          groupValue: 'p1',
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final card = tester
        .widgetList<Material>(
          find.byType(Material),
        )
        .where((item) => item.shape is RoundedRectangleBorder)
        .toList();
    expect(card, isNotEmpty, reason: '配置卡必须由 Material 承载底色');
    expect(
      card.first.color?.a,
      greaterThan(0.5),
      reason: '配置卡底色必须不透明，否则会透出页面背景',
    );
  });

  testWidgets('selected profile shows the current badge', (tester) async {
    await tester.pumpWidget(
      wrap(
        ProfileItem(
          profile: profile,
          groupValue: 'p1',
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    // 当前配置用主色边框 + 「当前」徽标区分，不再是整卡反色。
    expect(find.byType(SettingsIconTile), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('unselected profile shows its type badge', (tester) async {
    await tester.pumpWidget(
      wrap(
        ProfileItem(
          profile: profile,
          groupValue: null,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(SettingsIconTile), findsOneWidget);
  });
}
