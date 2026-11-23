/// 一次延迟采样。
///
/// [delay] 为 null 表示这次测速失败(超时 / 拒绝),这是重要信息 ——
/// 成功率比单次延迟更能说明节点成色。
class DelaySample {
  final int time;
  final int? delay;

  const DelaySample({required this.time, required this.delay});

  bool get isSuccess => delay != null && delay! > 0;

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(time);

  factory DelaySample.fromJson(Map<String, dynamic> json) {
    return DelaySample(
      time: (json['t'] as num?)?.toInt() ?? 0,
      delay: (json['d'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {'t': time, 'd': delay};
}
