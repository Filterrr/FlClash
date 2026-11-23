import 'package:fl_clash/common/low_memory_mode.dart';
import 'package:flutter/widgets.dart';

/// [KeepScope] 让子树在 PageView 里离开视口后仍保留 state
/// (AutomaticKeepAliveClientMixin)。
///
/// 低内存模式下主动放弃这份保留:离开视口的页面直接销毁,把它的
/// ScrollController / 图片 / 列表数据全部释放。代价是切回该页要重新
/// build 一次首帧,在内存吃紧时这笔交易是划算的。
///
/// wantKeepAlive 是动态值,Flutter 要求变化时调用 updateKeepAlive()
/// 主动通知 KeepAlive 宿主,否则它不会重新评估 —— 只改 getter 是无效的。
class KeepScope extends StatefulWidget {
  final Widget child;
  final bool keep;

  const KeepScope({
    super.key,
    required this.child,
    this.keep = true,
  });

  @override
  State<KeepScope> createState() => _KeepContainerState();
}

class _KeepContainerState extends State<KeepScope>
    with AutomaticKeepAliveClientMixin {
  @override
  void initState() {
    super.initState();
    lowMemoryModeNotifier.addListener(_handleLowMemoryModeChanged);
  }

  @override
  void dispose() {
    lowMemoryModeNotifier.removeListener(_handleLowMemoryModeChanged);
    super.dispose();
  }

  void _handleLowMemoryModeChanged() {
    if (!mounted) return;
    updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }

  @override
  bool get wantKeepAlive => widget.keep && !isLowMemoryMode;
}
