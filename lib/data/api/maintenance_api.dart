import '../../core/api_client.dart';

/// 闲置照片扫描结果（只读 dry run）
class OrphanScanResult {
  const OrphanScanResult({
    required this.total,
    required this.referenced,
    required this.orphans,
    required this.keys,
  });

  /// `tasks/` 前缀下的对象总数
  final int total;

  /// `total - orphans`（包含 6 小时保护期内的新图）
  final int referenced;

  /// 可清理的闲置照片数（全量计数）
  final int orphans;

  /// 闲置 key 列表（服务端最多回前 200 个）
  final List<String> keys;

  factory OrphanScanResult.fromJson(Map<String, dynamic> json) => OrphanScanResult(
        total: (json['total'] as num?)?.round() ?? 0,
        referenced: (json['referenced'] as num?)?.round() ?? 0,
        orphans: (json['orphans'] as num?)?.round() ?? 0,
        keys: (json['keys'] is List)
            ? (json['keys'] as List).whereType<String>().toList()
            : <String>[],
      );
}

/// 清理结果
class OrphanCleanResult {
  const OrphanCleanResult({
    required this.deleted,
    required this.failed,
    required this.keys,
  });

  final int deleted;
  final int failed;

  /// 已删除的 key（服务端最多回前 200 个，但实际删除不受此限）
  final List<String> keys;

  factory OrphanCleanResult.fromJson(Map<String, dynamic> json) => OrphanCleanResult(
        deleted: (json['deleted'] as num?)?.round() ?? 0,
        failed: (json['failed'] as num?)?.round() ?? 0,
        keys: (json['keys'] is List)
            ? (json['keys'] as List).whereType<String>().toList()
            : <String>[],
      );
}

/// 闲置照片维护（设置页「清理闲置照片」用）。
///
/// 判定口径：R2 `tasks/` 下存在、**没有任何流水引用**、且写入时间早于 6 小时前。
/// 拿不到写入时间或时间在未来的一律不删（保守）。
class MaintenanceApi {
  MaintenanceApi(this._api);

  final ApiClient _api;

  static const String path = '/api/maintenance/orphans';

  Future<OrphanScanResult> scan() async {
    final raw = await _api.getJson<Map<String, dynamic>>(path);
    if (raw == null) return const OrphanScanResult(total: 0, referenced: 0, orphans: 0, keys: <String>[]);
    return OrphanScanResult.fromJson(raw);
  }

  /// 危险操作：body 必须是**严格布尔** `{"confirm": true}`
  Future<OrphanCleanResult> clean() async {
    final raw = await _api.postJson<Map<String, dynamic>>(
      path,
      data: <String, dynamic>{'confirm': true},
    );
    if (raw == null) return const OrphanCleanResult(deleted: 0, failed: 0, keys: <String>[]);
    return OrphanCleanResult.fromJson(raw);
  }
}
