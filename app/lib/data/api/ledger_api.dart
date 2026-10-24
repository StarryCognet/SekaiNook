import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/ledger_ids.dart';
import '../models/ledger_record.dart';
import '../models/task_config.dart';

/// 全量余额（对应 Web 版 `LedgerSummary`）：
/// 家庭积分与花园阳光，由服务端整表聚合，不受「最近 200 条」窗口限制。
class LedgerSummary {
  const LedgerSummary({required this.family, required this.sun});

  final num family;
  final num sun;
}

/// 日结算结果（对应 Web 版 `LedgerSettleResult`）
class LedgerSettleResult {
  const LedgerSettleResult({
    required this.family,
    required this.sun,
    required this.applied,
    required this.day,
  });

  /// 结算后的家庭积分余额
  final num family;

  /// 结算后的花园阳光余额
  final num sun;

  /// 本次实际入账了哪几条（服务端幂等 id，重复调用会是空数组）
  final List<String> applied;

  /// **被结算的那一天**（东八区 YYYY-MM-DD）—— 可能不是今天，节流键要存这个值
  final String day;
}

/// 轮询用的账本快照：一次请求拿齐「余额 + 待审批 + 流水窗口」。
///
/// 见 `functions/api/ledger/snapshot.ts`。轮询频率高，把原来三个接口
/// （`/api/ledger`、`/api/ledger?status=pending`、`/api/ledger/summary`）
/// 合成一次往返。
class LedgerSnapshot {
  const LedgerSnapshot({
    required this.family,
    required this.sun,
    required this.pending,
    required this.records,
  });

  final num family;
  final num sun;
  final List<LedgerRecord> pending;
  final List<LedgerRecord> records;
}

/// 账本接口（对应 Web 版 `src/api/familyLedger.ts`）。
///
/// 花园流水和家庭账本共用同一张表、同一批接口，靠 task_id 前缀区分，
/// 具体见 `core/ledger_ids.dart`。
class LedgerApi {
  LedgerApi(this._client);

  final ApiClient _client;

  /// 拉最近一段流水（后端固定窗口，通常是最新 200 条），不分页参数
  Future<List<LedgerRecord>> fetchRecords() async {
    final raw = await _client.getJson<List<dynamic>>('/api/ledger');
    return _parseRecords(raw);
  }

  /// 一次拉齐余额、待审批与流水窗口（轮询专用）。
  ///
  /// 老部署没有这个路由（或返回格式不对）时返回 null，
  /// 调用方回退到「三次请求」的旧路径 —— 保证前后端可以分别上线。
  Future<LedgerSnapshot?> fetchSnapshot() async {
    try {
      final raw = await _client.getJson<dynamic>('/api/ledger/snapshot');
      return _toSnapshot(raw);
    } catch (_) {
      return null;
    }
  }

  /// 待审批的打卡申请，按 created_at 倒序
  Future<List<LedgerRecord>> fetchPendingRequests() async {
    final raw = await _client.getJson<List<dynamic>>(
      '/api/ledger',
      query: const <String, dynamic>{'status': 'pending'},
    );
    return _parseRecords(raw);
  }

  /// 拉全量余额。
  ///
  /// 老部署没有这个路由时会抛错，由调用方回退到流水求和 ——
  /// 但流水只有最近 200 条，所以**能拿到 summary 就一定要用 summary**，
  /// 否则余额会越用越少。
  Future<LedgerSummary> fetchLedgerSummary() async {
    final raw = await _client.getJson<dynamic>('/api/ledger/summary');
    final summary = _toSummary(raw);
    if (summary == null) {
      throw const ApiException('余额接口返回的格式不对', 0);
    }
    return summary;
  }

  /// 触发一次日结算（`POST /api/ledger/settle`，请求体可空）。
  ///
  /// 正确性完全由服务端幂等 id 保证（开户礼金 / 每日不足 5 个任务 / 睡觉罚款），
  /// 所以这里**失败一律静默返回 null** —— 结算失败绝不能挡住页面。
  /// 调用方的本地节流只为省流量，**不得当成防重复扣的手段**。
  Future<LedgerSettleResult?> settleLedger() async {
    try {
      final raw = await _client.postJson<dynamic>(
        '/api/ledger/settle',
        data: const <String, dynamic>{},
      );
      return _toSettleResult(raw);
    } catch (_) {
      return null;
    }
  }

  /// 写一条流水的底层入口（对应 `postLedgerRecord`）。
  ///
  /// 名称 / 类型 / 金额一律由服务端规则决定，客户端只给 task_id 与幂等 id
  /// —— **重试必须复用同一个 requestId**，靠服务端主键去重。
  /// 只有「金额由客户端指定」的历史迁移（garden_legacy）才额外传 amount。
  Future<LedgerWriteResult> postLedgerRecord(
    String taskId, {
    required String requestId,
    int? amount,
    String? name,
    TaskType? type,
    String? note,
    String? imageUrl,
  }) async {
    final raw = await _client.postJson<Map<String, dynamic>>(
      '/api/ledger',
      data: <String, dynamic>{
        'id': requestId,
        'task_id': taskId,
        'task_name': name ?? taskId,
        'type': (type ?? TaskType.earning).wire,
        'amount': amount ?? 0,
        'note': note,
        'image_url': imageUrl,
      },
      retry: true,
    );
    return LedgerWriteResult.fromJson(raw ?? const <String, dynamic>{});
  }

  /// 插入一条积分流水（对应 `addLedgerRecord`），返回新记录 id。
  ///
  /// 审批状态不由客户端决定：服务端一律写成 pending（花园奖励等 autoApprove 的除外），
  /// 只有 PATCH 才能改成 approved。家长自己记的账 / 兑现传 [autoApprove] 走
  /// 「提交 + 立即审批」两步。
  ///
  /// 抛出 [LedgerApprovalException] 表示记账成功但审批失败 ——
  /// 钱还挂在余额上，记录以 pending 躺在待审批里，**调用方必须让用户看见**。
  Future<String> addLedgerRecord(
    TaskConfig task, {
    String? note,
    String? imageUrl,
    String? requestId,
    bool autoApprove = false,
  }) async {
    final id = requestId ?? createRequestId();
    final result = await postLedgerRecord(
      task.id,
      requestId: id,
      amount: task.value,
      name: task.name,
      type: task.type,
      note: note,
      imageUrl: imageUrl,
    );
    if (autoApprove && result.id.isNotEmpty) {
      try {
        await updateStatus(result.id, LedgerStatus.approved);
      } catch (_) {
        // 不能吞：账已经记上了，调用方若照常报「余额清零」就是在骗人
        throw LedgerApprovalException(result.id);
      }
    }
    return result.id;
  }

  /// 修改某条流水的审批状态（reason 只在驳回时有意义，会带给孩子看）
  Future<void> updateStatus(String id, LedgerStatus status, {String? reason}) async {
    await _client.patchJson<dynamic>(
      '/api/ledger/${Uri.encodeComponent(id)}',
      data: <String, dynamic>{
        'status': status.wire,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
  }

  /// 审批通过
  Future<void> approveRequest(String id) => updateStatus(id, LedgerStatus.approved);

  /// 审批驳回，可附一句给女儿的话
  Future<void> rejectRequest(String id, {String? reason}) =>
      updateStatus(id, LedgerStatus.rejected, reason: reason);

  /// 驳回后重新提交：状态置回 pending
  Future<void> resubmitRequest(String id) => updateStatus(id, LedgerStatus.pending);

  /// 删除一条流水（仅家长）；若含图片，后端会一并删除 R2 中的图片
  Future<void> deleteLedgerRecord(String id) async {
    await _client.deleteJson<dynamic>('/api/ledger/${Uri.encodeComponent(id)}');
  }

  /// 计算家庭已入账积分：仅统计无状态（存量）或已审批的记录，且**不含花园阳光**
  static num calcApprovedBalance(List<LedgerRecord> records) => _calcBalance(records, false);

  /// 计算花园阳光余额：只统计花园相关且已入账的记录
  static num calcGardenBalance(List<LedgerRecord> records) => _calcBalance(records, true);

  static num _calcBalance(List<LedgerRecord> records, bool garden) {
    num sum = 0;
    for (final record in records) {
      if (record.isCredited && record.isGarden == garden) sum += record.amount;
    }
    return sum;
  }

  // ---- 解析 ----

  static List<LedgerRecord> _parseRecords(List<dynamic>? raw) {
    if (raw == null) return const <LedgerRecord>[];
    final result = <LedgerRecord>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) result.add(LedgerRecord.fromJson(item));
    }
    return result;
  }

  /// 只认字段齐全的快照响应，别把错误页 / 半截响应当成空数据
  static LedgerSnapshot? _toSnapshot(dynamic raw) {
    if (raw is! Map) return null;
    final family = raw['family'];
    final sun = raw['sun'];
    final pending = raw['pending'];
    final records = raw['records'];
    if (family is! num || !family.isFinite) return null;
    if (sun is! num || !sun.isFinite) return null;
    if (pending is! List || records is! List) return null;
    return LedgerSnapshot(
      family: family,
      sun: sun,
      pending: _parseRecords(pending),
      records: _parseRecords(records),
    );
  }

  /// 只认「两个字段都是有限数字」的响应，别把错误页 / 空对象当成余额 0
  static LedgerSummary? _toSummary(dynamic raw) {
    if (raw is! Map) return null;
    final family = raw['family'];
    final sun = raw['sun'];
    if (family is! num || !family.isFinite) return null;
    if (sun is! num || !sun.isFinite) return null;
    return LedgerSummary(family: family, sun: sun);
  }

  /// 只认字段齐全的结算响应，别把错误页 / 空对象当成「结算过了」
  static LedgerSettleResult? _toSettleResult(dynamic raw) {
    if (raw is! Map) return null;
    final family = raw['family'];
    final sun = raw['sun'];
    final day = raw['day'];
    final applied = raw['applied'];
    if (family is! num || !family.isFinite) return null;
    if (sun is! num || !sun.isFinite) return null;
    if (day is! String || day.isEmpty) return null;
    if (applied is! List) return null;
    final ids = <String>[];
    for (final item in applied) {
      if (item is! String) return null;
      ids.add(item);
    }
    return LedgerSettleResult(family: family, sun: sun, applied: ids, day: day);
  }
}
