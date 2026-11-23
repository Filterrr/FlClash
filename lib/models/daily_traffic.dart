/// 单日流量累计(字节)。
///
/// 手写模型,不走 codegen —— 存储格式就是它自己的 toJson,不需要为
/// 三个字段引入生成器。
class DailyTraffic {
  int up;
  int down;

  DailyTraffic({this.up = 0, this.down = 0});

  int get total => up + down;

  factory DailyTraffic.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return DailyTraffic(
      up: asInt(json['up']),
      down: asInt(json['down']),
    );
  }

  Map<String, dynamic> toJson() => {'up': up, 'down': down};
}
