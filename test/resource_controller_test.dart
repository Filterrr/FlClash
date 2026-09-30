import 'dart:async';

import 'package:fl_clash/common/low_memory_mode.dart';
import 'package:fl_clash/common/resource_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// ResourceController 回归测试。
///
/// 重点覆盖低内存模式切换时的订阅暂停/恢复配对，避免出现
/// 「进入 low 模式后订阅再也不会恢复」这类状态泄漏。
void main() {
  // ResourceController 是单例，且 _handleModeChange 依赖 PaintingBinding
  // （flutter_test 会自动初始化 binding），因此每个用例前重置模式。
  setUp(() {
    lowMemoryModeNotifier.value = LowMemoryMode.normal;
  });

  tearDown(() {
    lowMemoryModeNotifier.value = LowMemoryMode.normal;
    resourceController.dispose();
  });

  testWidgets('low 模式暂停非 critical 订阅，normal 模式恢复', (tester) async {
    resourceController.init();
    final controller = StreamController<int>.broadcast();
    var received = 0;
    final subscription = controller.stream.listen((_) => received++);
    resourceController.registerPausableSubscription(subscription);

    controller.add(1);
    await tester.pump();
    expect(received, 1);

    lowMemoryModeNotifier.value = LowMemoryMode.low;
    controller.add(2);
    await tester.pump();
    expect(received, 1, reason: 'low 模式应暂停订阅');

    lowMemoryModeNotifier.value = LowMemoryMode.normal;
    controller.add(3);
    await tester.pump();
    // pause() 会缓冲暂停期间的事件，resume() 后一并投递，
    // 因此这里只断言「投递已恢复」。
    expect(received, greaterThan(1), reason: '恢复 normal 后订阅应继续投递');

    await subscription.cancel();
    await controller.close();
  });

  testWidgets('critical 订阅在 low 模式下保持投递', (tester) async {
    resourceController.init();
    final controller = StreamController<int>.broadcast();
    var received = 0;
    final subscription = controller.stream.listen((_) => received++);
    resourceController.registerPausableSubscription(
      subscription,
      priority: ResourcePriority.critical,
    );

    lowMemoryModeNotifier.value = LowMemoryMode.low;
    controller.add(1);
    await tester.pump();
    expect(received, 1, reason: 'critical 订阅不受 low 模式影响');

    await subscription.cancel();
    await controller.close();
  });

  testWidgets('reduced 模式仅暂停 low 优先级订阅', (tester) async {
    resourceController.init();
    final normalController = StreamController<int>.broadcast();
    final lowController = StreamController<int>.broadcast();
    var normalReceived = 0;
    var lowReceived = 0;
    final normalSub = normalController.stream.listen((_) => normalReceived++);
    final lowSub = lowController.stream.listen((_) => lowReceived++);
    resourceController.registerPausableSubscription(normalSub);
    resourceController.registerPausableSubscription(
      lowSub,
      priority: ResourcePriority.low,
    );

    lowMemoryModeNotifier.value = LowMemoryMode.reduced;
    normalController.add(1);
    lowController.add(1);
    await tester.pump();
    expect(normalReceived, 1, reason: 'normal 优先级在 reduced 下仍投递');
    expect(lowReceived, 0, reason: 'low 优先级在 reduced 下被暂停');

    lowMemoryModeNotifier.value = LowMemoryMode.normal;
    lowController.add(2);
    await tester.pump();
    // 暂停期间的事件被缓冲，恢复后补发
    expect(lowReceived, greaterThan(0), reason: '恢复后 low 优先级订阅应继续');

    await normalSub.cancel();
    await lowSub.cancel();
    await normalController.close();
    await lowController.close();
  });

  testWidgets('unregister 后模式切换不再影响该订阅', (tester) async {
    resourceController.init();
    final controller = StreamController<int>.broadcast();
    var received = 0;
    final subscription = controller.stream.listen((_) => received++);
    resourceController.registerPausableSubscription(subscription);
    resourceController.unregisterPausableSubscription(subscription);

    lowMemoryModeNotifier.value = LowMemoryMode.low;
    controller.add(1);
    await tester.pump();
    expect(received, 1, reason: '已注销的订阅不应再被暂停');

    await subscription.cancel();
    await controller.close();
  });
}
