import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';

/// 订阅到期检查工具
class SubscriptionExpiryChecker {
  /// 到期提醒阈值（天）
  static const int expiryWarningDays = 7;

  /// 检查所有订阅的到期状态，返回需要提醒的列表
  static List<Profile> checkExpiringProfiles(List<Profile> profiles) {
    final now = DateTime.now();
    final warningThreshold = now.add(const Duration(days: expiryWarningDays));
    final expiring = <Profile>[];

    for (final profile in profiles) {
      final info = profile.subscriptionInfo;
      if (info == null || info.expire == 0) continue;

      final expiryDate =
          DateTime.fromMillisecondsSinceEpoch(info.expire * 1000);
      if (expiryDate.isBefore(now) || expiryDate.isBefore(warningThreshold)) {
        expiring.add(profile);
      }
    }
    return expiring;
  }

  /// 显示到期提醒
  static void showExpiryNotification(BuildContext context, Profile profile) {
    final info = profile.subscriptionInfo;
    if (info == null || info.expire == 0) return;

    final expiryDate =
        DateTime.fromMillisecondsSinceEpoch(info.expire * 1000);
    final now = DateTime.now();
    final isExpired = expiryDate.isBefore(now);
    final daysRemaining = expiryDate.difference(now).inDays;

    final title = isExpired
        ? appLocalizations.subscriptionExpired
        : appLocalizations.subscriptionExpiring;
    final message = isExpired
        ? appLocalizations.subscriptionExpiredDesc
        : appLocalizations.subscriptionExpiringDesc(daysRemaining);

    globalState.showMessage(
      title: title,
      message: TextSpan(
        children: [
          TextSpan(text: '${profile.label ?? profile.id}\n'),
          TextSpan(text: message),
        ],
      ),
    );
  }

  /// 在应用启动时检查到期状态
  static void checkOnStartup(List<Profile> profiles) {
    final expiring = checkExpiringProfiles(profiles);
    for (final profile in expiring) {
      final info = profile.subscriptionInfo!;
      final expiryDate =
          DateTime.fromMillisecondsSinceEpoch(info.expire * 1000);
      final now = DateTime.now();
      final isExpired = expiryDate.isBefore(now);

      if (isExpired) {
        globalState.appController.appFlowingState.addLog(
          Log(
            logLevel: LogLevel.warning,
            payload:
                '${profile.label ?? profile.id}: ${appLocalizations.subscriptionExpired}',
          ),
        );
      } else {
        globalState.appController.appFlowingState.addLog(
          Log(
            logLevel: LogLevel.info,
            payload:
                '${profile.label ?? profile.id}: ${appLocalizations.subscriptionExpiring}',
          ),
        );
      }
    }
  }
}
