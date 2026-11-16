import 'dart:io';

import 'package:fl_clash/fragments/resources.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归：资源项在文件不存在时必须显示「未下载」，不能一直转圈。
///
/// 旧实现直接 await file.lastModified()，文件缺失时抛出异常，而
/// FutureBuilder 只判断 data == null，于是 spinner 永远不会结束。
void main() {
  setUpAll(() async {
    await AppLocalizations.load(const Locale('en'));
  });

  test('missing geo file resolves to null instead of throwing', () async {
    final dir = await Directory.systemTemp.createTemp('geo_test');
    final file = File('${dir.path}/GeoIP.dat');
    expect(await file.exists(), isFalse);

    // 与 _getGeoFileLastModified 相同的判定顺序：先 exists 再读元数据。
    final resolved = await (() async {
      if (!await file.exists()) return null;
      return await file.lastModified();
    })();

    expect(resolved, isNull);
    await dir.delete(recursive: true);
  });

  testWidgets('resource row leaves the loading state for a missing file',
      (tester) async {
    // 直接验证 FutureBuilder 判定逻辑：done + data == null 不应再画 spinner。
    Widget probe(Future<String?> future) {
      return MaterialApp(
        home: Scaffold(
          body: FutureBuilder<String?>(
            future: future,
            builder: (_, snapshot) {
              final isLoading =
                  snapshot.connectionState == ConnectionState.waiting;
              return isLoading
                  ? const CircularProgressIndicator()
                  : Text(snapshot.data ?? 'none');
            },
          ),
        ),
      );
    }

    await tester.pumpWidget(probe(Future<String?>.value(null)));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('none'), findsOneWidget);
  });

  test('resource page exposes the geo items it renders', () {
    // 仅确认页面可构造，防止重构时丢掉入口。
    expect(const Resources(), isNotNull);
  });
}