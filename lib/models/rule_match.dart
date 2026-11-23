/// 分流诊断结果:一次规则匹配的完整答案。
///
/// 手写而非 codegen:这里不值得为几个字段引入 build_runner 的生成物,
/// 也就免了「改模型还要同步 .g.dart」这套负担。
class RuleMatchResult {
  /// 是否命中任何规则。为 false 时通常意味着配置里没有 MATCH 兜底。
  final bool matched;

  /// 命中规则的类型,例如 DOMAIN-SUFFIX / GEOIP / MATCH。
  final String rule;

  /// 规则的匹配内容,例如域名后缀、IP 段、规则集名。
  final String payload;

  /// 命中后落到哪里:策略组名,或 DIRECT / REJECT 这类内置目标。
  final String adapter;

  const RuleMatchResult({
    required this.matched,
    required this.rule,
    required this.payload,
    required this.adapter,
  });

  static const empty = RuleMatchResult(
    matched: false,
    rule: '',
    payload: '',
    adapter: '',
  );

  factory RuleMatchResult.fromJson(Map<String, dynamic> json) {
    return RuleMatchResult(
      matched: json['matched'] == true,
      rule: json['rule']?.toString() ?? '',
      payload: json['payload']?.toString() ?? '',
      adapter: json['adapter']?.toString() ?? '',
    );
  }

  /// 把结果压成一行人类可读的规则文本,便于直接复制回配置。
  String get ruleText {
    if (!matched) return '';
    if (payload.isEmpty) return '$rule,$adapter';
    return '$rule,$payload,$adapter';
  }
}
