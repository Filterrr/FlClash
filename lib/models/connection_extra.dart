/// 连接的扩展信息:规则命中、ASN、GeoIP、进程路径等。
///
/// 为什么不直接塞进 [Metadata]:那是 `@freezed` 模型,加字段要同步
/// 改 `.freezed.dart` + `.g.dart` 两个生成文件,而这个仓库在 CI 之外
/// 没有跑 codegen 的环节,手改生成物是明确的雷区。
///
/// 改法是旁挂:`ClashCore.getConnections()` 每次刷新时顺手把扩展信息
/// 按连接 id 存进 [connectionExtraStore],详情 UI 用 id 去查。
/// 对现有模型和调用点零侵入。
class ConnectionExtra {
  /// 命中规则的类型,例如 DomainSuffix / GeoIP。
  final String rule;

  /// 规则的匹配内容。
  final String rulePayload;

  final String destinationIPASN;
  final String sourceIPASN;
  final List<String> destinationGeoIP;
  final List<String> sourceGeoIP;

  /// 进程完整路径(Android 上通常拿不到,桌面端可用)。
  final String processPath;

  /// TLS SNI / HTTP Host 嗅探结果。
  final String sniffHost;

  /// DNS 解析模式:normal / fake-ip / mapping。
  final String dnsMode;

  final String specialProxy;
  final String specialRules;

  const ConnectionExtra({
    required this.rule,
    required this.rulePayload,
    required this.destinationIPASN,
    required this.sourceIPASN,
    required this.destinationGeoIP,
    required this.sourceGeoIP,
    required this.processPath,
    required this.sniffHost,
    required this.dnsMode,
    required this.specialProxy,
    required this.specialRules,
  });

  static const empty = ConnectionExtra(
    rule: '',
    rulePayload: '',
    destinationIPASN: '',
    sourceIPASN: '',
    destinationGeoIP: [],
    sourceGeoIP: [],
    processPath: '',
    sniffHost: '',
    dnsMode: '',
    specialProxy: '',
    specialRules: '',
  );

  factory ConnectionExtra.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'];
    final meta = metadata is Map ? metadata : const {};
    String asString(dynamic value) {
      if (value == null) return '';
      final text = value.toString();
      return text == '<nil>' ? '' : text;
    }

    List<String> asList(dynamic value) {
      if (value is List) {
        return value
            .map((e) => e?.toString() ?? '')
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return const [];
    }

    return ConnectionExtra(
      rule: asString(json['rule']),
      rulePayload: asString(json['rulePayload']),
      destinationIPASN: asString(meta['destinationIPASN']),
      sourceIPASN: asString(meta['sourceIPASN']),
      destinationGeoIP: asList(meta['destinationGeoIP']),
      sourceGeoIP: asList(meta['sourceGeoIP']),
      processPath: asString(meta['processPath']),
      sniffHost: asString(meta['sniffHost']),
      dnsMode: asString(meta['dnsMode']),
      specialProxy: asString(meta['specialProxy']),
      specialRules: asString(meta['specialRules']),
    );
  }

  bool get isEmpty =>
      rule.isEmpty &&
      destinationIPASN.isEmpty &&
      destinationGeoIP.isEmpty &&
      processPath.isEmpty &&
      sniffHost.isEmpty &&
      dnsMode.isEmpty;
}

/// 按连接 id 旁挂扩展信息的缓存。
///
/// 每次 `getConnections()` 整体替换 —— 连接列表本身就是全量的,
/// 增量维护只会引入不一致。
class ConnectionExtraStore {
  final Map<String, ConnectionExtra> _map = {};

  ConnectionExtra? operator [](String id) => _map[id];

  void replaceAll(Map<String, ConnectionExtra> next) {
    _map
      ..clear()
      ..addAll(next);
  }

  void clear() => _map.clear();

  int get length => _map.length;
}

final connectionExtraStore = ConnectionExtraStore();
