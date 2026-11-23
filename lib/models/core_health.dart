/// core 运行时健康状况快照(由 Go 侧 getMemoryStats 导出)。
///
/// 单位:除 [gcCPUFraction] 为比例外,其余均为字节。
class CoreMemoryStats {
  final int alloc;
  final int totalAlloc;
  final int sys;
  final int heapAlloc;
  final int heapSys;
  final int heapInuse;
  final int heapReleased;
  final int stackInuse;
  final int numGC;
  final int numForcedGC;

  /// GC 占用的 CPU 时间比例(0.0 ~ 1.0)。
  final double gcCPUFraction;

  const CoreMemoryStats({
    required this.alloc,
    required this.totalAlloc,
    required this.sys,
    required this.heapAlloc,
    required this.heapSys,
    required this.heapInuse,
    required this.heapReleased,
    required this.stackInuse,
    required this.numGC,
    required this.numForcedGC,
    required this.gcCPUFraction,
  });

  static const empty = CoreMemoryStats(
    alloc: 0,
    totalAlloc: 0,
    sys: 0,
    heapAlloc: 0,
    heapSys: 0,
    heapInuse: 0,
    heapReleased: 0,
    stackInuse: 0,
    numGC: 0,
    numForcedGC: 0,
    gcCPUFraction: 0,
  );

  factory CoreMemoryStats.fromJson(Map<String, dynamic> json) {
    int asInt(String key) => (json[key] as num?)?.toInt() ?? 0;
    return CoreMemoryStats(
      alloc: asInt('alloc'),
      totalAlloc: asInt('totalAlloc'),
      sys: asInt('sys'),
      heapAlloc: asInt('heapAlloc'),
      heapSys: asInt('heapSys'),
      heapInuse: asInt('heapInUse'),
      heapReleased: asInt('heapReleased'),
      stackInuse: asInt('stackInUse'),
      numGC: asInt('numGC'),
      numForcedGC: asInt('numForcedGC'),
      // Go 侧为了不丢精度,把这个浮点数放大 1e6 传过来
      gcCPUFraction: asInt('gcCPUFraction') / 1e6,
    );
  }

  bool get isEmpty => sys == 0 && heapAlloc == 0;

  /// 当前已从堆还给操作系统的字节数 —— 后台 FreeOSMemory 的实际战果。
  int get reclaimedBytes => heapReleased;
}
