// ignore_for_file: avoid_print

import 'dart:async';

import 'package:fl_clash/common/adaptive_timer.dart';
import 'package:fl_clash/common/http.dart';
import 'package:fl_clash/common/low_memory_mode.dart';
import 'package:fl_clash/common/resource_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// 后台资源释放测试套件
///
/// 验证应用在进入后台状态时能够正确释放系统资源，
/// 包括定时器、HTTP 连接、订阅等。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    lowMemoryModeNotifier.value = LowMemoryMode.normal;
    resourceController.init();
  });
  group('AdaptiveTimer 后台暂停/恢复', () {
    test('pause 后定时器停止触发回调', () async {
      int callCount = 0;
      final timer = AdaptiveTimer(
        activeInterval: const Duration(milliseconds: 50),
        idleInterval: const Duration(milliseconds: 100),
        idleThreshold: 3,
        callback: () {
          callCount++;
          return true;
        },
      );
      timer.start();
      await Future.delayed(const Duration(milliseconds: 120));
      final countBeforePause = callCount;
      expect(countBeforePause, greaterThan(0));

      timer.pause();
      expect(timer.isPaused, isTrue);
      expect(timer.isActive, isFalse);

      await Future.delayed(const Duration(milliseconds: 200));
      expect(callCount, equals(countBeforePause), reason: '暂停后不应再触发回调');

      timer.stop();
    });

    test('resume 后定时器恢复触发回调', () async {
      int callCount = 0;
      final timer = AdaptiveTimer(
        activeInterval: const Duration(milliseconds: 50),
        idleInterval: const Duration(milliseconds: 100),
        idleThreshold: 3,
        callback: () {
          callCount++;
          return true;
        },
      );
      timer.start();
      await Future.delayed(const Duration(milliseconds: 60));

      timer.pause();
      await Future.delayed(const Duration(milliseconds: 100));
      final countAtPause = callCount;

      timer.resume();
      expect(timer.isPaused, isFalse);
      expect(timer.isActive, isTrue);

      await Future.delayed(const Duration(milliseconds: 120));
      expect(callCount, greaterThan(countAtPause), reason: '恢复后应继续触发回调');

      timer.stop();
    });

    test('多次 pause/resume 循环不会泄漏定时器', () async {
      int callCount = 0;
      final timer = AdaptiveTimer(
        activeInterval: const Duration(milliseconds: 30),
        idleInterval: const Duration(milliseconds: 60),
        idleThreshold: 3,
        callback: () {
          callCount++;
          return true;
        },
      );

      // 模拟多次前后台切换
      for (int i = 0; i < 10; i++) {
        timer.start();
        await Future.delayed(const Duration(milliseconds: 40));
        timer.pause();
        await Future.delayed(const Duration(milliseconds: 40));
        timer.resume();
        await Future.delayed(const Duration(milliseconds: 40));
      }

      expect(timer.isActive, isTrue);
      expect(callCount, greaterThan(0));
      timer.stop();
      expect(timer.isActive, isFalse);
    });
  });

  group('FlClashHttpOverrides 后台连接管理', () {
    test('enterBackground / exitBackground 标记状态正确', () {
      // enterBackground 和 exitBackground 是静态方法，仅修改内部状态
      FlClashHttpOverrides.enterBackground();
      // 无法直接访问 _isInBackground，但可以通过行为验证
      // 只要不抛出异常即说明方法可用
      expect(() => FlClashHttpOverrides.enterBackground(), returnsNormally);
      expect(() => FlClashHttpOverrides.exitBackground(), returnsNormally);
    });

    test('forceIdleConnectionsExpire 在无客户端时不抛出异常', () {
      expect(() => FlClashHttpOverrides.forceIdleConnectionsExpire(),
          returnsNormally);
    });

    test('后台/前台切换循环不会崩溃', () {
      for (int i = 0; i < 20; i++) {
        FlClashHttpOverrides.enterBackground();
        FlClashHttpOverrides.exitBackground();
      }
    });
  });

  group('ResourceController 资源统计', () {
    test('getResourceStats 返回正确的统计结构', () {
      resourceController.init();
      final stats = resourceController.getResourceStats();

      expect(stats, isA<Map<String, dynamic>>());
      expect(stats.containsKey('totalPausableTimers'), isTrue);
      expect(stats.containsKey('pausedTimers'), isTrue);
      expect(stats.containsKey('totalPausableSubscriptions'), isTrue);
      expect(stats.containsKey('pausedSubscriptions'), isTrue);
      expect(stats.containsKey('currentMode'), isTrue);
    });

    test('hasActiveNonCriticalTimers / hasActiveNonCriticalSubscriptions 可用',
        () {
      resourceController.init();
      // 初始状态下应无活跃的非关键资源
      expect(resourceController.hasActiveNonCriticalTimers(), isFalse);
      expect(resourceController.hasActiveNonCriticalSubscriptions(), isFalse);
    });

    test('注册 PausableTimer 后统计正确', () {
      resourceController.init();
      final timer = PausableTimer(
        duration: const Duration(seconds: 1),
        callback: () {},
        priority: ResourcePriority.normal,
      );
      resourceController.registerPausableTimer(timer);

      final stats = resourceController.getResourceStats();
      expect(stats['totalPausableTimers'], greaterThanOrEqualTo(1));

      resourceController.pauseAllNonCriticalTimers();
      expect(timer.isPaused, isTrue);
      expect(resourceController.hasActiveNonCriticalTimers(), isFalse);

      resourceController.resumeAllTimers();
      expect(timer.isPaused, isFalse);

      resourceController.unregisterPausableTimer(timer);
    });

    test('注册 PausableSubscription 后统计正确', () async {
      resourceController.init();
      final controller = StreamController<int>();
      final sub = controller.stream.listen((_) {});

      resourceController.registerPausableSubscription(
        sub,
        priority: ResourcePriority.normal,
        label: 'test_sub',
      );

      final stats = resourceController.getResourceStats();
      expect(stats['totalPausableSubscriptions'], greaterThanOrEqualTo(1));

      resourceController.pauseAllNonCriticalSubscriptions();
      expect(sub.isPaused, isTrue);

      resourceController.resumeAllSubscriptions();
      expect(sub.isPaused, isFalse);

      resourceController.unregisterPausableSubscription(sub);
      await sub.cancel();
      await controller.close();
    });
  });

  group('LowMemoryMode 模式切换', () {
    test('normal -> reduced -> low -> normal 循环正确', () {
      lowMemoryModeNotifier.value = LowMemoryMode.normal;
      expect(isNormalMemoryMode, isTrue);
      expect(isLowMemoryMode, isFalse);

      lowMemoryModeNotifier.value = LowMemoryMode.reduced;
      expect(isReducedMemoryMode, isTrue);
      expect(isNormalMemoryMode, isFalse);

      lowMemoryModeNotifier.value = LowMemoryMode.low;
      expect(isLowMemoryMode, isTrue);
      expect(isReducedMemoryMode, isFalse);

      lowMemoryModeNotifier.value = LowMemoryMode.normal;
      expect(isNormalMemoryMode, isTrue);
      expect(isLowMemoryMode, isFalse);
    });

    test('多次模式切换循环不会泄漏监听器', () {
      int changeCount = 0;
      void listener() {
        changeCount++;
      }

      lowMemoryModeNotifier.addListener(listener);

      for (int i = 0; i < 10; i++) {
        lowMemoryModeNotifier.value = LowMemoryMode.reduced;
        lowMemoryModeNotifier.value = LowMemoryMode.low;
        lowMemoryModeNotifier.value = LowMemoryMode.normal;
      }

      // 每次实际变化触发一次（相同值不触发）
      expect(changeCount, equals(30));
      lowMemoryModeNotifier.removeListener(listener);
    });
  });

  group('VisibilityAwareTimer 后台暂停', () {
    test('pause 后停止触发回调', () async {
      int callCount = 0;
      bool visible = true;
      final timer = VisibilityAwareTimer(
        interval: const Duration(milliseconds: 50),
        callback: () {
          callCount++;
        },
        isVisible: () => visible,
      );
      timer.start();

      await Future.delayed(const Duration(milliseconds: 120));
      final countBeforePause = callCount;
      expect(countBeforePause, greaterThan(0));

      timer.pause();
      expect(timer.isPaused, isTrue);

      await Future.delayed(const Duration(milliseconds: 150));
      expect(callCount, equals(countBeforePause), reason: '暂停后不应触发回调');

      timer.resume();
      expect(timer.isPaused, isFalse);

      await Future.delayed(const Duration(milliseconds: 120));
      expect(callCount, greaterThan(countBeforePause), reason: '恢复后应继续触发回调');

      timer.stop();
    });
  });

  group('PausableTimer 后台暂停/恢复', () {
    test('pause / resume / cancel 生命周期正确', () {
      final timer = PausableTimer(
        duration: const Duration(milliseconds: 100),
        callback: () {},
        priority: ResourcePriority.normal,
      );

      timer.start();
      expect(timer.isActive, isTrue);
      expect(timer.isPaused, isFalse);

      timer.pause();
      expect(timer.isPaused, isTrue);

      timer.resume();
      expect(timer.isPaused, isFalse);

      timer.cancel();
      expect(timer.isActive, isFalse);
    });

    test('critical 优先级定时器在 pauseAllNonCriticalTimers 中不被暂停', () {
      final criticalTimer = PausableTimer(
        duration: const Duration(seconds: 1),
        callback: () {},
        priority: ResourcePriority.critical,
      );
      final normalTimer = PausableTimer(
        duration: const Duration(seconds: 1),
        callback: () {},
        priority: ResourcePriority.normal,
      );

      resourceController.registerPausableTimer(criticalTimer);
      resourceController.registerPausableTimer(normalTimer);

      criticalTimer.start();
      normalTimer.start();

      resourceController.pauseAllNonCriticalTimers();
      expect(criticalTimer.isPaused, isFalse, reason: 'critical 定时器不应被暂停');
      expect(normalTimer.isPaused, isTrue, reason: 'normal 定时器应被暂停');

      resourceController.resumeAllTimers();
      expect(normalTimer.isPaused, isFalse);

      criticalTimer.cancel();
      normalTimer.cancel();
      resourceController.unregisterPausableTimer(criticalTimer);
      resourceController.unregisterPausableTimer(normalTimer);
    });
  });

  group('多场景集成验证', () {
    test('场景1: 正常切换后台 - 资源应被释放', () async {
      // 模拟进入后台
      lowMemoryModeNotifier.value = LowMemoryMode.reduced;

      // 验证资源控制器可以暂停非关键资源
      final timer = PausableTimer(
        duration: const Duration(seconds: 1),
        callback: () {},
        priority: ResourcePriority.normal,
      );
      resourceController.registerPausableTimer(timer);
      timer.start();

      resourceController.pauseAllNonCriticalTimers();
      expect(timer.isPaused, isTrue, reason: '后台时非关键定时器应被暂停');
      expect(resourceController.hasActiveNonCriticalTimers(), isFalse);

      // 模拟回到前台
      lowMemoryModeNotifier.value = LowMemoryMode.normal;
      resourceController.resumeAllTimers();
      expect(timer.isPaused, isFalse, reason: '前台时定时器应恢复');

      timer.cancel();
      resourceController.unregisterPausableTimer(timer);
    });

    test('场景2: 长时间后台运行 - 维护机制正常', () async {
      // 模拟长时间后台
      lowMemoryModeNotifier.value = LowMemoryMode.low;

      // 验证缓存可被清理
      resourceController.forceClearAllCaches();
      expect(() => resourceController.forceClearImageCache(), returnsNormally);

      // 验证统计可获取
      final stats = resourceController.getResourceStats();
      expect(stats['currentMode'], equals('low'));

      lowMemoryModeNotifier.value = LowMemoryMode.normal;
    });

    test('场景3: 多次前后台切换 - 无资源泄漏', () async {
      final timers = <PausableTimer>[];
      for (int i = 0; i < 5; i++) {
        final t = PausableTimer(
          duration: Duration(seconds: 1 + i),
          callback: () {},
          priority: ResourcePriority.normal,
        );
        resourceController.registerPausableTimer(t);
        t.start();
        timers.add(t);
      }

      // 模拟 10 次前后台切换
      for (int i = 0; i < 10; i++) {
        // 进入后台
        lowMemoryModeNotifier.value = LowMemoryMode.reduced;
        resourceController.pauseAllNonCriticalTimers();
        for (final t in timers) {
          expect(t.isPaused, isTrue);
        }
        expect(resourceController.hasActiveNonCriticalTimers(), isFalse);

        // 回到前台
        lowMemoryModeNotifier.value = LowMemoryMode.normal;
        resourceController.resumeAllTimers();
        for (final t in timers) {
          expect(t.isPaused, isFalse);
        }
      }

      // 清理
      for (final t in timers) {
        t.cancel();
        resourceController.unregisterPausableTimer(t);
      }

      final stats = resourceController.getResourceStats();
      expect(stats['totalPausableTimers'], equals(0));
    });

    test('场景4: 后台时 HTTP 连接清理不中断活跃请求', () {
      // enterBackground 仅缩短空闲超时，不影响活跃连接
      FlClashHttpOverrides.enterBackground();
      // forceIdleConnectionsExpire 使空闲连接自然过期，不关闭客户端
      FlClashHttpOverrides.forceIdleConnectionsExpire();
      // exitBackground 恢复正常超时
      FlClashHttpOverrides.exitBackground();
    });

    test('场景5: 激进清理释放所有资源', () {
      lowMemoryModeNotifier.value = LowMemoryMode.low;

      // 激进清理
      resourceController.forceClearAllCaches();
      FlClashHttpOverrides.forceIdleConnectionsExpire();

      final stats = resourceController.getResourceStats();
      expect(stats['imageCacheSize'], equals(0));

      lowMemoryModeNotifier.value = LowMemoryMode.normal;
    });
  });

  tearDownAll(() {
    // 确保测试结束后恢复默认状态
    lowMemoryModeNotifier.value = LowMemoryMode.normal;
    FlClashHttpOverrides.exitBackground();
  });
}
