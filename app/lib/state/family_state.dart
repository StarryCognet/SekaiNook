import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_constants.dart';
import '../core/pin_guard.dart';
import '../data/api/ledger_api.dart';
import '../data/models/ledger_record.dart';

/// 当前身份：家长（可审批）/ 小孩（打卡需审批）
enum FamilyRole {
  parent('parent'),
  child('child');

  const FamilyRole(this.wire);
  final String wire;

  static FamilyRole? parse(String? raw) {
    for (final role in FamilyRole.values) {
      if (role.wire == raw) return role;
    }
    return null;
  }
}

/// 家庭积分银行全局状态（对应 Web 版 `src/store/useFamilyStore.ts`）。
///
/// 与 zustand 的差别：Dart 里没有 selector 浅比较，页面用 `context.select` 或
/// `Selector` 组件挑自己关心的字段即可；[ChangeNotifier] 的粒度靠调用方控制。
class FamilyState extends ChangeNotifier {
  FamilyState({
    required this.api,
    required this.pinGuard,
    required SharedPreferences prefs,
  }) : _prefs = prefs {
    _role = _loadRole();
  }

  final LedgerApi api;
  final PinGuard pinGuard;
  final SharedPreferences _prefs;

  // ---- 状态 ----

  FamilyRole? _role;

  /// 当前身份（null = 尚未选择，由身份选择门引导）
  FamilyRole? get role => _role;

  num _balance = 0;

  /// 家庭已入账积分（不含花园阳光）
  num get balance => _balance;

  List<LedgerRecord> _records = const <LedgerRecord>[];

  /// 家庭流水（**不含花园阳光**）：家长账本页看到的就是这些
  List<LedgerRecord> get records => _records;

  List<LedgerRecord> _gardenRecords = const <LedgerRecord>[];

  /// 花园阳光流水（同一个账本、另一个视图）
  List<LedgerRecord> get gardenRecords => _gardenRecords;

  num _sunBalance = 0;

  /// 花园阳光余额
  num get sunBalance => _sunBalance;

  List<LedgerRecord> _pendingRecords = const <LedgerRecord>[];

  /// 待审批申请列表
  List<LedgerRecord> get pendingRecords => _pendingRecords;

  int _pendingCount = 0;

  /// 待审批申请数量
  int get pendingCount => _pendingCount;

  bool _loading = false;
  bool get loading => _loading;

  /// 请求序号 —— 同一个接口会被多路轮询同时打：
  /// 底部导航 15 秒刷待审批、账本页家长态 10 秒、账本页小孩态 15 秒、两端首页 20 秒，
  /// 切回前台时还会再各来一次。
  /// 慢的旧响应如果后到，会把新数据覆盖回去（余额、待审批角标莫名回跳）。
  /// 这里只让「最新一次请求」的结果落库，旧响应直接丢弃。
  int _ledgerSeq = 0;
  int _pendingSeq = 0;

  // ---- 身份 ----

  /// 从本地存储恢复身份。
  /// 未设置时返回 null（首次打开的设备），交给身份选择门让用户选 ——
  /// **不能缺省为家长**：否则妹妹的手机第一次打开就是家长模式，可以自己审批自己的申请。
  FamilyRole? _loadRole() => FamilyRole.parse(_prefs.getString(AppConstants.keyRole));

  /// 切换身份（持久化到本机）
  Future<void> setRole(FamilyRole role) async {
    await _prefs.setString(AppConstants.keyRole, role.wire);
    _role = role;
    notifyListeners();
  }

  /// 退出当前身份、回到身份选择门。
  /// Web 版没有这个入口，是 Flutter 版设置页新增的：只删本机身份键，
  /// 内存里的 role 必须一起清掉并 notify，否则 router 不会跳回 /role。
  Future<void> clearRole() async {
    await _prefs.remove(AppConstants.keyRole);
    _role = null;
    notifyListeners();
  }

  // ---- 口令（转发给 PinGuard，页面统一从 state 拿，省得各处再找 prefs）----

  /// 校验家长口令（异步比对摘要 + 失败锁定）；锁定期内即使输入正确也返回 false
  Future<bool> verifyParentPin(String pin) => pinGuard.verify(pin);

  /// 更新家长口令
  Future<void> setParentPin(String pin) => pinGuard.setParentPin(pin);

  /// 距离解锁还剩多少（0 = 未锁定）
  Duration get pinLockRemaining => pinGuard.lockRemaining;

  /// 还能试几次（锁定中为 0）
  int get pinAttemptsLeft => pinGuard.attemptsLeft;

  /// 是否用的是自己的家长口令（改回出厂口令 1234 也算没自定义）
  bool get hasCustomParentPin => pinGuard.hasCustomParentPin;

  // ---- 账本 ----

  /// 拉取流水与余额（单一数据源：余额优先用服务端全量聚合）与待审批数量
  Future<void> loadLedger() async {
    final seq = ++_ledgerSeq;
    _loading = true;
    notifyListeners();
    try {
      // 三个请求并发发出；summary 失败要有兜底，不能拖垮整次加载
      final recordsFuture = api.fetchRecords();
      final pendingFuture = api.fetchPendingRequests();
      final summaryFuture = _summaryOrNull();

      final allRecords = await recordsFuture;
      final pending = await pendingFuture;
      final summary = await summaryFuture;

      // 期间又有更新的一次请求发出去了 ⇒ 这份结果已经过期，丢掉（别覆盖新数据）
      if (seq != _ledgerSeq) return;

      // 同一个账本拆成两本：家长 / 家庭界面只看非花园流水，花园流水走 gardenRecords
      _records = allRecords.where((record) => !record.isGarden).toList(growable: false);
      _gardenRecords = allRecords.where((record) => record.isGarden).toList(growable: false);
      _pendingRecords = pending;
      _pendingCount = pending.length;
      // 全量余额单独兜底：老部署还没有 /api/ledger/summary 时退回用流水算，
      // 但流水只有最近 200 条，所以能拿到 summary 就一定要用 summary（否则余额会越用越少）
      _balance = summary?.family ?? LedgerApi.calcApprovedBalance(_records);
      _sunBalance = summary?.sun ?? LedgerApi.calcGardenBalance(_gardenRecords);
      _loading = false;
      notifyListeners();
    } catch (e) {
      if (seq == _ledgerSeq) {
        _loading = false;
        notifyListeners();
      }
      rethrow;
    }
  }

  /// 仅刷新待审批列表（轮询用）
  Future<void> refreshPending() async {
    final seq = ++_pendingSeq;
    final pending = await api.fetchPendingRequests();
    if (seq != _pendingSeq) return; // 同理：过期响应不落库
    _pendingRecords = pending;
    _pendingCount = pending.length;
    notifyListeners();
  }

  /// 审批通过
  Future<void> approve(String id) async {
    await api.approveRequest(id);
    await loadLedger();
  }

  /// 批量审批通过（逐条提交，最后统一刷新一次）
  ///
  /// 一条失败不拖累其余：整批先跑完，再统一刷新一次账本，
  /// 最后失败数大于 0 时抛错让界面提示「有 N 条没通过，请重试」。
  Future<void> approveMany(List<String> ids) async {
    final results = await Future.wait(
      ids.map(
        (id) => api
            .approveRequest(id)
            .then((_) => true)
            .catchError((Object _) => false),
      ),
    );
    await loadLedger();
    final failed = results.where((ok) => !ok).length;
    if (failed > 0) {
      throw StateError('有 $failed 条没通过，请重试');
    }
  }

  /// 审批驳回（reason 会原样带给孩子看）
  Future<void> reject(String id, {String? reason}) async {
    await api.rejectRequest(id, reason: reason);
    await loadLedger();
  }

  /// 驳回后重新提交（孩子端用）
  Future<void> resubmit(String id) async {
    await api.resubmitRequest(id);
    await loadLedger();
  }

  /// 删除一条流水（仅家长），后端会一并删除关联图片
  Future<void> removeRecord(String id) async {
    await api.deleteLedgerRecord(id);
    await loadLedger();
  }

  // ---- 日结算 ----

  /// 按「被结算的那一天」节流地触发一次结算：同一天已经结算过就不再发请求。
  ///
  /// ⚠️ 正确性完全由服务端幂等 id 保证（`daily_penalty_<day>` / `sleep_penalty_<day>`），
  /// 这里的节流纯粹为了省流量，**任何情况下都不能当成防重复扣的手段**
  /// —— 节流记录丢了最多多发一次请求，服务端会认出重复。
  ///
  /// 返回 null 表示「这一天已经结算过」或「请求失败」，两种都不该挡住页面。
  Future<LedgerSettleResult?> settleLedgerOncePerDay({DateTime? now}) async {
    final expected = expectedSettleDay(now ?? DateTime.now());
    if (_prefs.getString(AppConstants.keySettleDay) == expected) return null;
    final result = await api.settleLedger();
    if (result != null) {
      await _prefs.setString(AppConstants.keySettleDay, result.day);
    }
    return result;
  }

  /// 本地推算「本次会被结算的那一天」，与服务端 settleDay 同规则：
  /// 东八区 ≥22:00 记今天，否则记昨天。**只用于节流**，不作为任何正确性依据。
  static String expectedSettleDay(DateTime now) {
    final shifted = now.toUtc().add(const Duration(hours: 8));
    final day = shifted.hour < 22 ? shifted.subtract(const Duration(days: 1)) : shifted;
    return '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
  }

  Future<LedgerSummary?> _summaryOrNull() async {
    try {
      return await api.fetchLedgerSummary();
    } catch (_) {
      return null;
    }
  }
}

/// 把结算入账的 id 说成人话（罚款要说清原因，别甩一串英文 id 给孩子看）。
/// 对应 Web 版 `describeSettleApplied`。
String describeSettleApplied(Iterable<String> ids) {
  return ids.map((id) {
    if (id.startsWith('seed_welcome_bonus')) return '开户礼金 +100';
    if (id.startsWith('sleep_penalty')) return '到 22:00 还没打卡睡觉 -20';
    if (id.startsWith('daily_penalty') || id.startsWith('daily_min_tasks_penalty')) {
      return '那天完成的任务不够 5 个 -10';
    }
    if (id.startsWith('sleep_on_time')) return '按时打卡睡觉 +10';
    return id;
  }).join('；');
}
