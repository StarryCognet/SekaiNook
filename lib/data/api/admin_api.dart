import '../../core/api_client.dart';
import '../../core/api_exception.dart';

/// 管理员接口的余额快照（每次成功调用都会带回最新余额）
class AdminBalances {
  const AdminBalances({required this.family, required this.sun});

  final num family;
  final num sun;

  factory AdminBalances.fromJson(Map<String, dynamic> json) => AdminBalances(
        family: (json['family'] as num?) ?? 0,
        sun: (json['sun'] as num?) ?? 0,
      );
}

/// `adjust` 的结果：目标值 + 人类可读的变更说明
class AdminAdjustResult {
  const AdminAdjustResult({
    required this.family,
    required this.sun,
    required this.changed,
  });

  final num family;
  final num sun;

  /// 形如 `['家庭积分 20 → 500', '花园阳光 0 → 30']`；delta 为 0 的那本账不出现
  final List<String> changed;
}

/// 一条管理员调整记录（留痕，可在账本页删除撤销）
class AdminAdjustment {
  const AdminAdjustment({
    required this.id,
    required this.ledger,
    required this.amount,
    required this.note,
    required this.createdAt,
  });

  final String id;

  /// `'family'`（家庭积分）或 `'sun'`（花园阳光）
  final String ledger;
  final num amount;
  final String note;
  final DateTime? createdAt;

  bool get isSun => ledger == 'sun';

  factory AdminAdjustment.fromJson(Map<String, dynamic> json) => AdminAdjustment(
        id: (json['id'] ?? '') as String,
        ledger: (json['ledger'] ?? 'family') as String,
        amount: (json['amount'] as num?) ?? 0,
        note: (json['note'] ?? '') as String,
        createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '')?.toLocal(),
      );
}

class AdminAdjustmentList {
  const AdminAdjustmentList({
    required this.family,
    required this.sun,
    required this.adjustments,
  });

  final num family;
  final num sun;
  final List<AdminAdjustment> adjustments;
}

/// 管理员接口（`POST /api/admin`）—— **全站唯一的密码校验点**。
///
/// 只有一个 POST 入口，靠 `action` 分流：
/// `verify`（默认）/ `password` / `adjust` / `adjustments`。
///
/// 两个必须注意的行为：
/// 1. **未知 `action` 会被静默按 `verify` 处理并返回 200** ——
///    所以 Dart 端自己要枚举校验，不能靠服务端报错。
/// 2. 锁定期内（连错 5 次锁 5 分钟）**正确密码也一律 429**。
class AdminApi {
  AdminApi(this._api);

  final ApiClient _api;

  static const String path = '/api/admin';

  /// 出厂密码（服务端 `DEFAULT_ADMIN_PASSWORD`），只在文档里，客户端不预填
  static const int passwordMinLength = 4;
  static const int passwordMaxLength = 32;

  /// 单次调整绝对值上限（防手滑多打几位）
  static const num maxAdjustAbs = 1000000;

  Future<AdminBalances> verify(String password) async {
    final raw = await _post(<String, dynamic>{
      'password': password,
      'action': 'verify',
    });
    return AdminBalances.fromJson(raw);
  }

  Future<AdminBalances> changePassword(String password, String newPassword) async {
    final raw = await _post(<String, dynamic>{
      'password': password,
      'action': 'password',
      'newPassword': newPassword,
    });
    return AdminBalances.fromJson(raw);
  }

  /// 把余额改成目标值（**不是加/减**）。
  ///
  /// 省略 `family` / `sun` 键 = 不改那本账；显式传 0 是合法的目标值。
  /// delta 为 0 时服务端什么都不写（重复提交天然幂等）。
  Future<AdminAdjustResult> adjust(
    String password, {
    num? family,
    num? sun,
  }) async {
    final raw = await _post(<String, dynamic>{
      'password': password,
      'action': 'adjust',
      if (family != null) 'family': family,
      if (sun != null) 'sun': sun,
    });
    final changed = raw['changed'];
    return AdminAdjustResult(
      family: (raw['family'] as num?) ?? 0,
      sun: (raw['sun'] as num?) ?? 0,
      changed: changed is List ? changed.whereType<String>().toList() : <String>[],
    );
  }

  Future<AdminAdjustmentList> fetchAdjustments(String password) async {
    final raw = await _post(<String, dynamic>{
      'password': password,
      'action': 'adjustments',
    });
    final list = raw['adjustments'];
    final adjustments = <AdminAdjustment>[];
    if (list is List) {
      for (final item in list) {
        if (item is Map) {
          adjustments
              .add(AdminAdjustment.fromJson(item.map((key, value) => MapEntry(key.toString(), value))));
        }
      }
    }
    return AdminAdjustmentList(
      family: (raw['family'] as num?) ?? 0,
      sun: (raw['sun'] as num?) ?? 0,
      adjustments: adjustments,
    );
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final raw = await _api.postJson<Map<String, dynamic>>(path, data: body);
    if (raw == null) throw const ApiException('管理员接口没有返回内容', 0);
    return raw;
  }
}
