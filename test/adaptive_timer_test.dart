import 'package:fl_clash/common/adaptive_timer.dart';
import 'package:fl_clash/common/low_memory_mode.dart';
import 'package:flutter_test/flutter_test.dart';

/// AdaptiveTimer 回归测试。
///
/// 重点覆盖 reduced 模式下的跳帧逻辑：被跳过的 tick 必须继续推进
/// `_idleTicks`，否则跳帧判定 `_idleTicks % N == 0` 会永远命中同一个
/// 余数，导致定时器在首次触发后彻底停摆（曾导致主轮询只执行一次）。
void main() {
  tearDown(() {
    lowMemoryModeNotifier.value = LowMemoryMode.normal;
  });

  AdaptiveTimer buildTimer({
    required bool Function() callback,
    int idleThreshold = 1000,
    int deepIdleThreshold = 2000,
  }) {
    return AdaptiveTimer(
      activeInterval: const Duration(milliseconds: 10),
      idleInterval: const Duration(milliseconds: 100),
      deepIdleInterval: const Duration(milliseconds: 300),
      idleThreshold: idleThreshold,
      deepIdleThreshold: deepIdleThreshold,
      callback: callback,
      // 测试环境不触碰真实 core：clashCore 是惰性单例，一旦初始化会
      // 拉起 ClashService（socket / 子进程 / 周期定时器）。
      requestGc: () {},
    );
  }

  testWidgets('normal 模式下每个 tick 都触发回调', (tester) async {
    var calls = 0;
    final timer = buildTimer(callback: () {
      calls++;
      return true;
    });
    timer.start();
    await tester.pump(const Duration(milliseconds: 100));
    timer.stop();
    expect(calls, 10);
  });

  testWidgets('low 模式下完全暂停回调', (tester) async {
    lowMemoryModeNotifier.value = LowMemoryMode.low;
    var calls = 0;
    final timer = buildTimer(callback: () {
      calls++;
      return false;
    });
    timer.start();
    await tester.pump(const Duration(milliseconds: 300));
    timer.stop();
    expect(calls, 0);
  });

  testWidgets('reduced 模式下按 1/3 频率持续触发（核心回归：不再停摆）',
      (tester) async {
    lowMemoryModeNotifier.value = LowMemoryMode.reduced;
    var calls = 0;
    final timer = buildTimer(callback: () {
      calls++;
      return false;
    });
    timer.start();
    await tester.pump(const Duration(milliseconds: 300));
    timer.stop();
    // 修复前：_idleTicks 停在 1，回调仅执行 1 次后永久停摆。
    // 修复后：每 3 个 tick 执行 1 次，300ms/10ms=30 tick -> 10 次。
    expect(calls, 10, reason: 'reduced 模式下回调必须持续推进，不得停摆');
  });

  testWidgets('reduced 恢复到 normal 后回到全速', (tester) async {
    lowMemoryModeNotifier.value = LowMemoryMode.reduced;
    var calls = 0;
    final timer = buildTimer(callback: () {
      calls++;
      return false;
    });
    timer.start();
    await tester.pump(const Duration(milliseconds: 150));
    final reducedCalls = calls;
    expect(reducedCalls, 5);

    lowMemoryModeNotifier.value = LowMemoryMode.normal;
    await tester.pump(const Duration(milliseconds: 100));
    timer.stop();
    expect(calls - reducedCalls, 10, reason: '恢复 normal 后应回到每 tick 执行');
  });

  testWidgets('空闲达到阈值后降频，且仍持续触发', (tester) async {
    var calls = 0;
    final timer = buildTimer(
      callback: () {
        calls++;
        return false; // 始终无变化 -> 应降频
      },
      idleThreshold: 3,
      deepIdleThreshold: 6,
    );
    timer.start();
    await tester.pump(const Duration(milliseconds: 800));
    timer.stop();
    // 降频后仍须有回调，且总次数应显著少于不降频时的 80 次
    expect(calls, greaterThan(5), reason: '降频后仍应持续回调');
    expect(calls, lessThan(80), reason: '降频应显著减少回调次数');
  });
}
