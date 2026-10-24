import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_constants.dart';
import '../config/garden_config.dart';
import '../core/api_exception.dart';
import '../core/ledger_ids.dart';
import '../data/api/ledger_api.dart';
import '../data/models/garden.dart';
import '../data/models/ledger_record.dart';
import '../data/models/pending_garden_op.dart';
import '../data/models/task_config.dart';

/// 老余额迁移流水的固定 id（重启重发同 id，服务端靠主键幂等）
const String migrationLegacyId = 'mig_legacy';

/// 老商城购买迁移流水的 id 前缀
const String migrationShopIdPrefix = 'mig_shop_';

/// 今日任务里「背古诗」那一项的固定 id
const String poemTaskId = 'poem';

/// 今日任务里「语文预习」那一项的固定 id
const String chineseTaskId = 'chinese';

/// 离线队列补发间隔（页面在前台时）
const Duration _flushInterval = Duration(seconds: 30);

/// 本地日期键（YYYY-MM-DD）。
///
/// 花园**只用设备本地时区** —— 东八区只存在于服务端日结算路径，
/// 两套「今天」口径不同，不要混用（不要拿 `WeekUtil.beijingDayKey` 替换）。
String toDateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 今日日期键（页面判断「今天是否已打卡」用）
String todayKey() => toDateKey(DateTime.now());

// ---- 读档期的脏数据清洗（六个函数，边界必须逐字复刻）----

/// 有限数且 > 0 → 取整，否则 0。**负数与 0 都归 0**（计数用）
int _toSafeCount(Object? value) {
  if (value is num && value.isFinite && value > 0) return value.floor();
  return 0;
}

/// 有限数 → 四舍五入，否则 0。**0 与负数保留**，所以不能复用 [_toSafeCount]（金额用）
int _toSafeAmount(Object? value) {
  if (value is num && value.isFinite) return value.round();
  return 0;
}

/// 非数组 → 空；数组只保留字符串项（不去重、不裁剪空串）
List<String> _toSafeStringArray(Object? value) {
  if (value is! List) return <String>[];
  return value.whereType<String>().toList();
}

/// 非空字符串 → 原值，否则 null（空串算「没设」）
String? _toSafeId(Object? value) => (value is String && value.isNotEmpty) ? value : null;

/// 非对象 → 空；每项过 [_toSafeCount]，只保留 > 0 的键
Map<String, int> _toSafeCountRecord(Object? value) {
  if (value is! Map) return <String, int>{};
  final result = <String, int>{};
  for (final entry in value.entries) {
    final count = _toSafeCount(entry.value);
    if (count > 0) result[entry.key.toString()] = count;
  }
  return result;
}

/// 连续学习天数：昨天活动过 → +1；今天已活动过 → 不变；断档 → 归 1
int _nextStreak(String? lastActiveDate, int streakDays, String today) {
  if (lastActiveDate == null) return 1;
  if (lastActiveDate == today) return streakDays;
  final yesterday = toDateKey(DateTime.now().subtract(const Duration(days: 1)));
  return lastActiveDate == yesterday ? streakDays + 1 : 1;
}

/// 勋章解锁判定（**单调**：只置 earned=true，从不撤销）
List<Badge> _resolveBadges(
  List<Badge> badges, {
  required int totalCompleted,
  required int balance,
  required int streakDays,
  required int poemCount,
  required int gardenCareDays,
}) {
  final unlocked = <String, bool>{
    'sunrise': totalCompleted >= 1,
    'gardener': totalCompleted >= 10,
    'streak3': streakDays >= 3,
    'week_champ': streakDays >= 7,
    'poet': poemCount >= 10,
    'plant_warrior': gardenCareDays >= 7,
    'sun_rich': balance >= 500,
  };
  return badges.map((badge) {
    if (unlocked[badge.id] == true && !badge.earned) return badge.copyWith(earned: true);
    return badge;
  }).toList();
}

/// 一次活动的累计统计（**不产 completedCount**：分子分母必须同口径）
class CompletionStats {
  const CompletionStats({
    required this.balance,
    required this.streakDays,
    required this.totalCompleted,
    required this.lastActiveDate,
    required this.todayEarned,
    required this.gardenCareDays,
    required this.lastGardenedDate,
  });

  final int balance;
  final int streakDays;
  final int totalCompleted;
  final String lastActiveDate;
  final int todayEarned;
  final int gardenCareDays;
  final String lastGardenedDate;
}

CompletionStats _nextCompletionStats(GardenState source, int reward, String today) {
  return CompletionStats(
    balance: source.balance + reward,
    streakDays: _nextStreak(source.lastActiveDate, source.streakDays, today),
    totalCompleted: source.totalCompleted + 1,
    lastActiveDate: today,
    todayEarned: (source.todayEarnedDate == today ? source.todayEarned : 0) + reward,
    gardenCareDays:
        source.lastGardenedDate == today ? source.gardenCareDays : source.gardenCareDays + 1,
    lastGardenedDate: today,
  );
}

/// 权威阳光基准的三段回退（导出给页面/测试复用）。
///
/// ① 全量接口值 → ② 本地花园流水求和 → ③ 上次存的 `cachedSun`。
/// 注意 `cachedRecords` **非空就采用 ②**，哪怕算出来是 0。
int resolveSunBase({
  required int? summarySun,
  required List<LedgerRecord> cachedRecords,
  required int cachedSun,
}) {
  if (summarySun != null) return summarySun;
  if (cachedRecords.isNotEmpty) return LedgerApi.calcGardenBalance(cachedRecords).round();
  return cachedSun;
}

PendingGardenOp _earnOp(String taskId, int amount) => PendingGardenOp(
      id: createRequestId(),
      taskId: taskId,
      kind: GardenOpKind.earn,
      amount: amount,
      at: DateTime.now().millisecondsSinceEpoch,
    );

PendingGardenOp _spendOp(String taskId, String itemId, int cost) => PendingGardenOp(
      id: createRequestId(),
      taskId: taskId,
      kind: GardenOpKind.spend,
      amount: -cost,
      itemId: itemId,
      at: DateTime.now().millisecondsSinceEpoch,
    );

/// 按 id 去重入队（同一个操作已经在队列里就不重复压）
List<PendingGardenOp> _pushOp(List<PendingGardenOp> pending, PendingGardenOp op) {
  if (pending.any((item) => item.id == op.id)) return pending;
  return <PendingGardenOp>[...pending, op];
}

bool _isMigrationOp(PendingGardenOp op) =>
    op.id == migrationLegacyId || op.id.startsWith(migrationShopIdPrefix);

/// 老数据迁移：把老余额 + 已购物品的钱一次性搬进来。
///
/// 确定性 id（`mig_legacy` / `mig_shop_<itemId>`）保证重启重发不会重复入账；
/// 老余额先加上已购物品的钱，随后补发的购买记录扣完，派生余额正好等于老余额。
List<PendingGardenOp> _buildMigrationOps(int legacyBalance, List<String> ownedItems) {
  final at = DateTime.now().millisecondsSinceEpoch;
  final ops = <PendingGardenOp>[];
  var ownedCost = 0;
  for (final itemId in ownedItems) {
    for (final item in GardenConfig.shopItems) {
      if (item.id == itemId) ownedCost += item.cost;
    }
  }
  // 服务端会把 garden_legacy 夹到 [0, GARDEN_LEGACY_MAX]：客户端先夹一次，两边算出来的数一致
  var legacyAmount = legacyBalance + ownedCost;
  if (legacyAmount < 0) legacyAmount = 0;
  if (legacyAmount > LedgerIds.gardenLegacyMax) legacyAmount = LedgerIds.gardenLegacyMax;
  if (legacyAmount > 0) {
    ops.add(PendingGardenOp(
      id: migrationLegacyId,
      taskId: LedgerIds.gardenLegacyTaskId,
      kind: GardenOpKind.earn,
      amount: legacyAmount,
      at: at,
    ));
  }
  for (final itemId in ownedItems) {
    GardenShopItem? found;
    for (final item in GardenConfig.shopItems) {
      if (item.id == itemId) found = item;
    }
    if (found == null) continue; // 不认识的物品（老版本删过的商品）搬不了，跳过
    ops.add(PendingGardenOp(
      id: '$migrationShopIdPrefix$itemId',
      taskId: LedgerIds.gardenShopTaskId(itemId),
      kind: GardenOpKind.spend,
      amount: -found.cost,
      itemId: itemId,
      at: at,
    ));
  }
  return ops;
}

/// 与账本并集（换手机后买到的东西还在）。
///
/// 起点是**本地清单本身**（不做差集：账本里没有的本地物品不会被移除），
/// 只吸收 `garden_shop:*` 且能在商品表里找到的 id，跳过 rejected。
List<String> _mergeOwnedItems(List<String> local, List<LedgerRecord> records) {
  final owned = <String>{...local};
  for (final record in records) {
    if (record.status == LedgerStatus.rejected) continue;
    final itemId = LedgerIds.gardenShopItemId(record.taskId);
    if (itemId == null) continue;
    if (GardenConfig.shopItems.any((item) => item.id == itemId)) owned.add(itemId);
  }
  return owned.toList();
}

/// 商城兑换结果
enum ShopBuyResult { ok, owned, insufficient, unknown }

/// 装备结果
enum EquipResult { ok, owned, unknown }

/// 花园状态（对应 Web 版 `src/store/useGardenStore.ts`）。
///
/// 与家庭账本的分工：家庭 store 管「积分」，这里管「阳光」。
/// 花园的持久化只在**本机**（`shared_preferences`），唯一跨设备的真相是账本流水 ——
/// `ownedItems` 靠账本里的 `garden_shop:*` 记录恢复，其余（tasks / 装备 / 勋章 /
/// 连续天数 / 背诗计数）完全不跨设备。
class GardenState extends ChangeNotifier {
  GardenState({required SharedPreferences prefs, required LedgerApi ledgerApi})
      : _prefs = prefs,
        _ledgerApi = ledgerApi;

  final SharedPreferences _prefs;
  final LedgerApi _ledgerApi;

  // ---- 状态字段 ----

  int _balance = 0;

  /// 花园阳光**显示余额** = `cachedSun + pendingDelta`。页面直接读它。
  int get balance => _balance;

  List<GardenTask> _tasks = <GardenTask>[];

  /// 今日任务列表（8 条，含 done / completedAt）
  List<GardenTask> get tasks => List<GardenTask>.unmodifiable(_tasks);

  List<Badge> _badges = <Badge>[];

  /// 7 枚勋章（含 earned）
  List<Badge> get badges => List<Badge>.unmodifiable(_badges);

  int _streakDays = 0;

  /// 连续学习天数（跨天累计，不重置）
  int get streakDays => _streakDays;

  int _completedCount = 0;

  /// **今日完成的花园任务数**，由 [tasks] 派生（永远 ≤ tasks.length）。
  /// 绝不改成「每次活动自增」—— 那会复现已修掉的历史 bug（老存档 11/8）。
  int get completedCount => _completedCount;

  int _totalCompleted = 0;

  /// **累计活动次数**（背 3 首诗算 3 次；不是去重后的天数）
  int get totalCompleted => _totalCompleted;

  String? _lastActiveDate;

  /// 最近一次活动日（本地时区 YYYY-MM-DD）
  String? get lastActiveDate => _lastActiveDate;

  int _poemCount = 0;

  /// 累计背会古诗首数
  int get poemCount => _poemCount;

  int _gardenCareDays = 0;

  /// 累计照顾花园自然日数
  int get gardenCareDays => _gardenCareDays;

  List<String> _ownedItems = <String>[];

  /// 已拥有商品 id
  List<String> get ownedItems => List<String>.unmodifiable(_ownedItems);

  String? _equippedAvatar;
  String? get equippedAvatar => _equippedAvatar;

  String? _equippedTitle;
  String? get equippedTitle => _equippedTitle;

  List<String> _equippedDecor = <String>[];

  /// 花园装饰 id 列表，最多 3 件，**先挂的在前**
  List<String> get equippedDecor => List<String>.unmodifiable(_equippedDecor);

  List<String> _todayPoemIds = <String>[];
  List<String> get todayPoemIds => List<String>.unmodifiable(_todayPoemIds);

  String _poemDate = '';
  String get poemDate => _poemDate;

  Map<String, int> _chineseSteps = <String, int>{};
  Map<String, int> get chineseSteps => Map<String, int>.unmodifiable(_chineseSteps);

  String _chineseDate = '';
  String get chineseDate => _chineseDate;

  int _todayEarned = 0;

  /// 今日实际入账阳光（商城消费不走它：花掉的不冲掉赚到的）
  int get todayEarned => _todayEarned;

  String _todayEarnedDate = '';
  String get todayEarnedDate => _todayEarnedDate;

  String? _lastWaterDate;

  /// 最近一次**浇水**的自然日（只管浇水）
  String? get lastWaterDate => _lastWaterDate;

  String? _lastGardenedDate;

  /// 最近一次「照顾花园」的自然日（去重基准）
  String? get lastGardenedDate => _lastGardenedDate;

  String _tasksDate = '';
  String get tasksDate => _tasksDate;

  int? _summarySun;

  /// 全量余额接口给的权威阳光（不含未同步增量）
  int? get summarySun => _summarySun;

  List<LedgerRecord> _cachedRecords = <LedgerRecord>[];

  /// 本地缓存的花园流水（仅按前缀过滤，**含 rejected**）
  List<LedgerRecord> get cachedRecords => List<LedgerRecord>.unmodifiable(_cachedRecords);

  int _cachedSun = 0;

  /// 上次算出的权威余额（离线冷启动兜底）。
  /// **字段名叫 cachedSun，存的却是 [resolveSunBase] 的结果**，不是「缓存余额」。
  int get cachedSun => _cachedSun;

  List<PendingGardenOp> _pending = <PendingGardenOp>[];

  /// 离线/未入账的乐观操作队列，**先到先发**
  List<PendingGardenOp> get pending => List<PendingGardenOp>.unmodifiable(_pending);

  int _pendingDelta = 0;

  /// 未同步增量金额之和
  int get pendingDelta => _pendingDelta;

  // ---- 模块级单例状态 ----

  /// 补发闸：并发调用**直接丢弃**（不是排队）
  bool _flushing = false;

  static bool _syncLoopReady = false;

  /// 存档是否已读进内存。启动、孩子首页、花园页都会调 [init]，
  /// 真源是内存状态（只有本进程写存档），重复读纯属白费一轮解析 + 一次 refreshLedger。
  bool _inited = false;

  bool _appVisible = true;

  /// 页面是否在前台（对应 Web 版 `document.hidden`）—— 后台不补发，省电
  void setAppVisible(bool visible) {
    _appVisible = visible;
    if (visible) unawaited(flushPending());
  }

  // ---- 存储 ----

  Map<String, dynamic> _loadState() {
    final raw = _prefs.getString(AppConstants.keyGardenState);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) return parsed;
      if (parsed is Map) return parsed.map((key, value) => MapEntry(key.toString(), value));
    } catch (_) {
      // 坏存档当作没有
    }
    return <String, dynamic>{};
  }

  /// 全量写回持久化子集（**每一次 commit 之后**）。
  /// 写入失败不能影响内存里的账。
  void _saveState() {
    final payload = <String, dynamic>{
      'balance': _balance,
      'tasks': _tasks.map((task) => task.toJson()).toList(),
      'badges': _badges.map((badge) => badge.toJson()).toList(),
      'streakDays': _streakDays,
      'completedCount': _completedCount,
      'totalCompleted': _totalCompleted,
      'lastActiveDate': _lastActiveDate,
      'poemCount': _poemCount,
      'gardenCareDays': _gardenCareDays,
      'ownedItems': _ownedItems,
      'equippedAvatar': _equippedAvatar,
      'equippedTitle': _equippedTitle,
      'equippedDecor': _equippedDecor,
      'todayPoemIds': _todayPoemIds,
      'poemDate': _poemDate,
      'chineseSteps': _chineseSteps,
      'chineseDate': _chineseDate,
      'todayEarned': _todayEarned,
      'todayEarnedDate': _todayEarnedDate,
      'lastWaterDate': _lastWaterDate,
      'lastGardenedDate': _lastGardenedDate,
      'tasksDate': _tasksDate,
      'cachedSun': _cachedSun,
    };
    try {
      _prefs.setString(AppConstants.keyGardenState, jsonEncode(payload));
    } catch (_) {
      // 隐私模式 / 配额满：这一份存不下就存不下，内存里的账照常
    }
  }

  /// 老数据迁移标志：判据是**键存在**（值恒为 '1'），不是值为真
  bool _readMigratedFlag() {
    try {
      return _prefs.getString(AppConstants.keyGardenMigrated) != null;
    } catch (_) {
      return false;
    }
  }

  void _writeMigratedFlag() {
    try {
      _prefs.setString(AppConstants.keyGardenMigrated, '1');
    } catch (_) {
      // 写不进去也不影响这次的账
    }
  }

  List<PendingGardenOp> _loadPending() {
    final raw = _prefs.getString(AppConstants.keyGardenPending);
    if (raw == null || raw.isEmpty) return <PendingGardenOp>[];
    try {
      return PendingGardenOp.listFromStored(jsonDecode(raw));
    } catch (_) {
      return <PendingGardenOp>[];
    }
  }

  /// 写离线队列（单独一个键：只有它变了才写，免得每次打卡都整车重写一遍）
  void _savePending() {
    try {
      _prefs.setString(
        AppConstants.keyGardenPending,
        jsonEncode(_pending.map((op) => op.toJson()).toList()),
      );
    } catch (_) {
      // 存不下就存不下：内存里的队列还在，本次会话照样补发
    }
  }

  // ---- commit ----

  /// 统一的提交口（对应 Web 版 `commit`）。
  ///
  /// 语义 = 「基于最新 state 计算补丁，再浅合并」。**必须复刻的两点**：
  /// ① 4 个派生字段（`pendingDelta` / `cachedSun` / `balance` / `completedCount`）
  /// 无条件重算；② 任何字段都可以通过 patch 覆盖。
  void _commit(Map<String, Object?> patch) {
    final summarySun =
        patch.containsKey('summarySun') ? patch['summarySun'] as int? : _summarySun;
    final cachedRecords = patch.containsKey('cachedRecords')
        ? patch['cachedRecords']! as List<LedgerRecord>
        : _cachedRecords;
    final pending =
        patch.containsKey('pending') ? patch['pending']! as List<PendingGardenOp> : _pending;
    final pendingDelta = pending.fold<int>(0, (sum, op) => sum + op.amount);
    final cachedSun = resolveSunBase(
      summarySun: summarySun,
      cachedRecords: cachedRecords,
      cachedSun: patch.containsKey('cachedSun') ? patch['cachedSun']! as int : _cachedSun,
    );
    final tasks = patch.containsKey('tasks') ? patch['tasks']! as List<GardenTask> : _tasks;
    final completedCount = tasks.where((task) => task.done).length;

    // 浅合并
    if (patch.containsKey('tasks')) _tasks = tasks;
    if (patch.containsKey('badges')) _badges = patch['badges']! as List<Badge>;
    if (patch.containsKey('streakDays')) _streakDays = patch['streakDays']! as int;
    if (patch.containsKey('totalCompleted')) _totalCompleted = patch['totalCompleted']! as int;
    if (patch.containsKey('lastActiveDate')) _lastActiveDate = patch['lastActiveDate'] as String?;
    if (patch.containsKey('poemCount')) _poemCount = patch['poemCount']! as int;
    if (patch.containsKey('gardenCareDays')) _gardenCareDays = patch['gardenCareDays']! as int;
    if (patch.containsKey('ownedItems')) _ownedItems = patch['ownedItems']! as List<String>;
    if (patch.containsKey('equippedAvatar')) _equippedAvatar = patch['equippedAvatar'] as String?;
    if (patch.containsKey('equippedTitle')) _equippedTitle = patch['equippedTitle'] as String?;
    if (patch.containsKey('equippedDecor')) _equippedDecor = patch['equippedDecor']! as List<String>;
    if (patch.containsKey('todayPoemIds')) _todayPoemIds = patch['todayPoemIds']! as List<String>;
    if (patch.containsKey('poemDate')) _poemDate = patch['poemDate']! as String;
    if (patch.containsKey('chineseSteps')) _chineseSteps = patch['chineseSteps']! as Map<String, int>;
    if (patch.containsKey('chineseDate')) _chineseDate = patch['chineseDate']! as String;
    if (patch.containsKey('todayEarned')) _todayEarned = patch['todayEarned']! as int;
    if (patch.containsKey('todayEarnedDate')) _todayEarnedDate = patch['todayEarnedDate']! as String;
    if (patch.containsKey('lastWaterDate')) _lastWaterDate = patch['lastWaterDate'] as String?;
    if (patch.containsKey('lastGardenedDate')) {
      _lastGardenedDate = patch['lastGardenedDate'] as String?;
    }
    if (patch.containsKey('tasksDate')) _tasksDate = patch['tasksDate']! as String;
    _summarySun = summarySun;
    _cachedRecords = cachedRecords;
    _pending = pending;
    _pendingDelta = pendingDelta;
    _cachedSun = cachedSun;
    _balance = cachedSun + pendingDelta;
    _completedCount = completedCount;

    _saveState();
    if (patch.containsKey('pending')) _savePending();
    notifyListeners();
  }

  // ---- 结算与补发 ----

  /// 出一笔队列（对应 `settleOp`）。
  ///
  /// `written`（已入账）：出队 + 把这笔金额从「未同步增量」搬进 [summarySun]
  /// —— **显示值在出队那一刻不跳变**。
  /// `rejected`（被明确拒绝）：earn 只出队（乐观加分撤掉）；
  /// spend 且带 itemId 时再收回物品（退款）。
  ///
  /// **不处理 `equipped*`**：被拒的购买若已被戴上，仍留在装备栏里（现状，有意照抄）。
  void _settleOp(PendingGardenOp op, {required bool written}) {
    final patch = <String, Object?>{
      'pending': _pending.where((item) => item.id != op.id).toList(),
    };
    if (written) {
      patch['summarySun'] = resolveSunBase(
            summarySun: _summarySun,
            cachedRecords: _cachedRecords,
            cachedSun: _cachedSun,
          ) +
          op.amount;
    } else if (op.kind == GardenOpKind.spend && op.itemId != null) {
      patch['ownedItems'] = _ownedItems.where((id) => id != op.itemId).toList();
    }
    _commit(patch);
  }

  void _markMigratedIfSettled() {
    if (_readMigratedFlag()) return;
    if (_pending.any(_isMigrationOp)) return;
    _writeMigratedFlag();
  }

  /// 补发离线队列。
  ///
  /// 严格顺序：**只发队头**，成功或被拒才继续下一笔；任何「暂时不通」的错误
  /// 直接 `break`（队头阻塞，后面的操作这次不发）。并发调用**直接丢弃**。
  Future<void> flushPending() async {
    if (_flushing) return;
    _flushing = true;
    var settled = 0;
    var migrationRejected = false;
    try {
      while (true) {
        if (_pending.isEmpty) break;
        final op = _pending.first;
        try {
          await _ledgerApi.postLedgerRecord(
            op.taskId,
            requestId: op.id,
            amount: op.amount,
            name: op.taskId,
            type: op.kind == GardenOpKind.spend ? TaskType.spending : TaskType.earning,
          );
          _settleOp(op, written: true);
          settled += 1;
        } catch (error) {
          if (error is! ApiException || !error.isRejectedWrite) break;
          if (_isMigrationOp(op)) migrationRejected = true;
          _settleOp(op, written: false);
          settled += 1;
        }
      }
      if (!migrationRejected) _markMigratedIfSettled();
    } finally {
      _flushing = false;
    }
    if (settled > 0) await refreshLedger();
  }

  Future<LedgerSummary?> _safeSummary() async {
    try {
      return await _ledgerApi.fetchLedgerSummary();
    } catch (_) {
      return null;
    }
  }

  Future<List<LedgerRecord>?> _safeRecords() async {
    try {
      return await _ledgerApi.fetchRecords();
    } catch (_) {
      return null;
    }
  }

  /// 拉全量余额与花园流水，校正本地。
  ///
  /// 两个请求并行、独立容忍；**两个都失败**才整体返回（连落盘都不发生
  /// —— 保留旧值，绝不因一次失败把阳光清零）。
  Future<void> refreshLedger() async {
    // 捕获 await 之前的本地清单（契约里的已知细节：可能已过期，只会少合并）
    final ownedBefore = List<String>.of(_ownedItems);
    // 先发出去再分别 await —— 两个请求真正并行（此前注释写了并行、实现是串行）
    final summaryFuture = _safeSummary();
    final recordsFuture = _safeRecords();
    final summary = await summaryFuture;
    final records = await recordsFuture;
    if (summary == null && records == null) return;

    final patch = <String, Object?>{};
    if (summary != null) patch['summarySun'] = summary.sun.round();
    if (records != null) {
      patch['cachedRecords'] =
          records.where((record) => LedgerIds.isGardenTaskId(record.taskId)).toList();
      patch['ownedItems'] = _mergeOwnedItems(ownedBefore, records);
    }
    _commit(patch);
  }

  /// 30 秒补发一次（页面隐藏时跳过）；只在首次调用时挂定时器。
  ///
  /// 对应 Web 版 `window online` 的部分由 [setAppVisible]（回到前台）代劳。
  void _ensureSyncLoop() {
    if (_syncLoopReady) return;
    _syncLoopReady = true;
    Timer.periodic(_flushInterval, (_) {
      if (!_appVisible) return;
      unawaited(flushPending());
    });
  }

  // ---- init ----

  /// 进入花园 / 应用启动时调用（**幂等**：首次真正读存档，之后只确保补发定时器）。
  ///
  /// 启动（app.dart）、孩子首页、花园页三处都会调；之前每次都重读存档 +
  /// 重新 refreshLedger，等于进一次花园多打一轮接口。
  void init() {
    if (_inited) {
      _ensureSyncLoop();
      return;
    }
    _inited = true;
    final saved = _loadState();
    final today = todayKey();

    final savedBalance = _toSafeCount(saved['balance']);
    final savedStreak = _toSafeCount(saved['streakDays']);
    final savedTotal = _toSafeCount(saved['totalCompleted']);
    final savedPoem = _toSafeCount(saved['poemCount']);
    final savedCare = _toSafeCount(saved['gardenCareDays']);

    final samePoemDay = saved['poemDate'] == today;
    final sameChineseDay = saved['chineseDate'] == today;
    final sameTaskDay = saved['tasksDate'] == today;
    final sameEarnedDay = saved['todayEarnedDate'] == today;

    final lastWaterDate = _toSafeId(saved['lastWaterDate']);
    // 老字段 lastCareDate：旧版本任务完成也写它
    final legacyCareDate = _toSafeId(saved['lastCareDate']);
    final lastGardenedDate = _toSafeId(saved['lastGardenedDate']) ?? legacyCareDate;

    List<GardenTask>? savedTasks;
    final rawTasks = saved['tasks'];
    if (rawTasks is List) {
      savedTasks = <GardenTask>[];
      for (final item in rawTasks) {
        if (item is Map) {
          savedTasks.add(GardenTask.fromJson(item.map((k, v) => MapEntry(k.toString(), v))));
        }
      }
    }

    // 老存档没有「今日入账」时，用当天已完成任务的 reward 求和兜底
    final legacyEarned = (sameTaskDay && savedTasks != null)
        ? savedTasks.where((task) => task.done).fold<int>(0, (sum, task) => sum + task.reward)
        : 0;

    final ownedItems = _toSafeStringArray(saved['ownedItems']);
    final migrated = _readMigratedFlag();
    final needsMigration = !migrated && (savedBalance > 0 || ownedItems.isNotEmpty);

    // 要迁移的老用户从 0 起算（老余额由迁移流水搬进来）
    final cachedSun = needsMigration
        ? 0
        : (saved['cachedSun'] is num
            ? _toSafeAmount(saved['cachedSun'])
            : _toSafeAmount(saved['balance']));

    var pending = _loadPending();
    for (final op in _buildMigrationOps(savedBalance, ownedItems)) {
      pending = _pushOp(pending, op);
    }

    List<Badge>? savedBadges;
    final rawBadges = saved['badges'];
    if (rawBadges is List) {
      savedBadges = <Badge>[];
      for (final item in rawBadges) {
        if (item is Map) {
          savedBadges.add(Badge.fromJson(item.map((k, v) => MapEntry(k.toString(), v))));
        }
      }
    }

    _commit(<String, Object?>{
      'tasks': sameTaskDay
          ? (savedTasks ?? List<GardenTask>.of(GardenConfig.tasks))
          : List<GardenTask>.of(GardenConfig.tasks),
      'badges': _resolveBadges(
        savedBadges ?? List<Badge>.of(GardenConfig.badges),
        totalCompleted: savedTotal,
        balance: savedBalance,
        streakDays: savedStreak,
        poemCount: savedPoem,
        gardenCareDays: savedCare,
      ),
      'streakDays': savedStreak,
      'totalCompleted': savedTotal,
      'lastActiveDate': saved['lastActiveDate'] is String ? saved['lastActiveDate'] : null,
      'poemCount': savedPoem,
      'gardenCareDays': savedCare,
      'ownedItems': ownedItems,
      'equippedAvatar': _toSafeId(saved['equippedAvatar']),
      'equippedTitle': _toSafeId(saved['equippedTitle']),
      'equippedDecor':
          _toSafeStringArray(saved['equippedDecor']).take(GardenConfig.maxDecor).toList(),
      'todayPoemIds': samePoemDay ? _toSafeStringArray(saved['todayPoemIds']) : <String>[],
      'poemDate': today,
      'chineseSteps': sameChineseDay ? _toSafeCountRecord(saved['chineseSteps']) : <String, int>{},
      'chineseDate': today,
      'todayEarned': sameEarnedDay ? _toSafeCount(saved['todayEarned']) : legacyEarned,
      'todayEarnedDate': today,
      'lastWaterDate': lastWaterDate,
      'lastGardenedDate': lastGardenedDate,
      'tasksDate': today,
      'cachedSun': cachedSun,
      'pending': pending,
      // 重复 init 时保留已拿到的权威值
      'summarySun': _summarySun,
      'cachedRecords': _cachedRecords,
      // 不传 completedCount：由 commit 从 tasks 派生
    });

    if (!needsMigration) _writeMigratedFlag();
    _ensureSyncLoop();
    unawaited(flushPending());
    unawaited(refreshLedger());
  }

  // ---- 动作 ----

  /// 完成一个今日任务。未知 id 或已完成 → 静默 no-op。
  void completeTask(String taskId) {
    GardenTask? task;
    for (final item in _tasks) {
      if (item.id == taskId) task = item;
    }
    if (task == null || task.done) return;

    final today = todayKey();
    final stats = _nextCompletionStats(this, task.reward, today);
    _commit(<String, Object?>{
      'tasks': _tasks
          .map((item) => item.id == taskId
              ? item.copyWith(done: true, completedAt: DateTime.now())
              : item)
          .toList(),
      'badges': _resolveBadges(
        _badges,
        totalCompleted: stats.totalCompleted,
        balance: stats.balance,
        streakDays: stats.streakDays,
        poemCount: _poemCount,
        gardenCareDays: stats.gardenCareDays,
      ),
      'streakDays': stats.streakDays,
      'totalCompleted': stats.totalCompleted,
      'lastActiveDate': stats.lastActiveDate,
      'gardenCareDays': stats.gardenCareDays,
      'lastGardenedDate': stats.lastGardenedDate,
      'todayEarned': stats.todayEarned,
      'todayEarnedDate': today,
      'todayPoemIds': _poemDate == today ? _todayPoemIds : <String>[],
      'poemDate': today,
      'chineseSteps': _chineseDate == today ? _chineseSteps : <String, int>{},
      'chineseDate': today,
      'tasksDate': today,
      'pending': _pushOp(_pending, _earnOp(LedgerIds.gardenTaskId(task.id), task.reward)),
    });
    unawaited(flushPending());
  }

  /// 背会一首古诗。返回 true = 计入并已入队；false = 未知诗或今日已背过。
  bool recitePoem(String poemId) {
    GardenPoem? poem;
    for (final item in GardenConfig.poems) {
      if (item.id == poemId) poem = item;
    }
    if (poem == null) return false;

    final today = todayKey();
    final todayPoemIds = _poemDate == today ? _todayPoemIds : <String>[];
    if (todayPoemIds.contains(poemId)) return false;

    var poemTaskDone = false;
    for (final item in _tasks) {
      if (item.id == poemTaskId && item.done) poemTaskDone = true;
    }
    final stats = _nextCompletionStats(this, poem.reward, today);
    final poemCount = _poemCount + 1;
    _commit(<String, Object?>{
      'tasks': poemTaskDone
          ? _tasks
          : _tasks
              .map((item) => item.id == poemTaskId
                  ? item.copyWith(done: true, completedAt: DateTime.now())
                  : item)
              .toList(),
      'badges': _resolveBadges(
        _badges,
        totalCompleted: stats.totalCompleted,
        balance: stats.balance,
        streakDays: stats.streakDays,
        poemCount: poemCount,
        gardenCareDays: stats.gardenCareDays,
      ),
      'streakDays': stats.streakDays,
      'totalCompleted': stats.totalCompleted,
      'lastActiveDate': stats.lastActiveDate,
      'poemCount': poemCount,
      'gardenCareDays': stats.gardenCareDays,
      'lastGardenedDate': stats.lastGardenedDate,
      'todayEarned': stats.todayEarned,
      'todayEarnedDate': today,
      'todayPoemIds': <String>[...todayPoemIds, poemId],
      'poemDate': today,
      'chineseSteps': _chineseDate == today ? _chineseSteps : <String, int>{},
      'chineseDate': today,
      // 注意：不写 tasksDate（照抄现状，别「顺手补上」）
      'pending': _pushOp(_pending, _earnOp(LedgerIds.gardenTaskId(poemTaskId), poem.reward)),
    });
    unawaited(flushPending());
    return true;
  }

  /// 完成一次语文练习打卡。返回 true = 计入并已入队；false = 未知练习或已达每日次数。
  bool completeChineseStep(String practiceId) {
    GardenChinesePractice? practice;
    for (final item in GardenConfig.chinesePractices) {
      if (item.id == practiceId) practice = item;
    }
    if (practice == null) return false;

    final today = todayKey();
    final steps = _chineseDate == today ? _chineseSteps : <String, int>{};
    final done = steps[practiceId] ?? 0;
    if (done >= practice.timesPerDay) return false;

    var chineseTaskDone = false;
    for (final item in _tasks) {
      if (item.id == chineseTaskId && item.done) chineseTaskDone = true;
    }
    final stats = _nextCompletionStats(this, practice.reward, today);
    _commit(<String, Object?>{
      'tasks': chineseTaskDone
          ? _tasks
          : _tasks
              .map((item) => item.id == chineseTaskId
                  ? item.copyWith(done: true, completedAt: DateTime.now())
                  : item)
              .toList(),
      'badges': _resolveBadges(
        _badges,
        totalCompleted: stats.totalCompleted,
        balance: stats.balance,
        streakDays: stats.streakDays,
        poemCount: _poemCount,
        gardenCareDays: stats.gardenCareDays,
      ),
      'streakDays': stats.streakDays,
      'totalCompleted': stats.totalCompleted,
      'lastActiveDate': stats.lastActiveDate,
      'gardenCareDays': stats.gardenCareDays,
      'lastGardenedDate': stats.lastGardenedDate,
      'todayEarned': stats.todayEarned,
      'todayEarnedDate': today,
      'todayPoemIds': _poemDate == today ? _todayPoemIds : <String>[],
      'poemDate': today,
      'chineseSteps': <String, int>{...steps, practiceId: done + 1},
      'chineseDate': today,
      'pending':
          _pushOp(_pending, _earnOp(LedgerIds.gardenTaskId(practiceId), practice.reward)),
    });
    unawaited(flushPending());
    return true;
  }

  /// 给花园浇水。返回 false = 今天已浇过。
  ///
  /// **不发阳光、不写后端、不进 pending**（服务端没有对应规则）。
  /// 「今天浇过水没有」只看 [lastWaterDate] —— 以前做完任务会把浇水顶掉，白点。
  bool careForGarden() {
    final today = todayKey();
    if (_lastWaterDate == today) return false;
    final gardenCareDays =
        _lastGardenedDate == today ? _gardenCareDays : _gardenCareDays + 1;
    _commit(<String, Object?>{
      'lastWaterDate': today,
      'lastGardenedDate': today,
      'gardenCareDays': gardenCareDays,
      'badges': _resolveBadges(
        _badges,
        totalCompleted: _totalCompleted,
        balance: _balance,
        streakDays: _streakDays,
        poemCount: _poemCount,
        gardenCareDays: gardenCareDays,
      ),
    });
    return true;
  }

  /// 兑换商品。拦截顺序：未知商品 → 已拥有 → 余额不足。
  /// 只做「拥有 + 扣钱」，**不自动装备**。
  ShopBuyResult buyItem(String itemId) {
    GardenShopItem? item;
    for (final candidate in GardenConfig.shopItems) {
      if (candidate.id == itemId) item = candidate;
    }
    if (item == null) return ShopBuyResult.unknown;
    if (_ownedItems.contains(itemId)) return ShopBuyResult.owned;
    if (_balance < item.cost) return ShopBuyResult.insufficient;

    _commit(<String, Object?>{
      'ownedItems': <String>[..._ownedItems, itemId],
      'pending': _pushOp(_pending, _spendOp(LedgerIds.gardenShopTaskId(itemId), itemId, item.cost)),
    });
    unawaited(flushPending());
    return ShopBuyResult.ok;
  }

  /// 装备商品（纯本地，不写后端）。装饰最多 3 件，挂满时淘汰**最早挂上的那件**。
  EquipResult equipItem(String itemId) {
    GardenShopItem? item;
    for (final candidate in GardenConfig.shopItems) {
      if (candidate.id == itemId) item = candidate;
    }
    if (item == null) return EquipResult.unknown;
    if (!_ownedItems.contains(itemId)) return EquipResult.owned;

    switch (item.category) {
      case GardenShopCategory.avatar:
        _commit(<String, Object?>{'equippedAvatar': itemId});
      case GardenShopCategory.title:
        _commit(<String, Object?>{'equippedTitle': itemId});
      case GardenShopCategory.decor:
        final rest = _equippedDecor.where((id) => id != itemId).toList();
        final kept = rest.length >= GardenConfig.maxDecor
            ? rest.sublist(rest.length - (GardenConfig.maxDecor - 1))
            : rest;
        _commit(<String, Object?>{'equippedDecor': <String>[...kept, itemId]});
    }
    return EquipResult.ok;
  }

  /// 摘下商品（幂等；摘下的物品**不会**从 [ownedItems] 移除）
  void unequipItem(String itemId) {
    GardenShopItem? item;
    for (final candidate in GardenConfig.shopItems) {
      if (candidate.id == itemId) item = candidate;
    }
    if (item == null) return;

    switch (item.category) {
      case GardenShopCategory.avatar:
        if (_equippedAvatar == itemId) _commit(<String, Object?>{'equippedAvatar': null});
      case GardenShopCategory.title:
        if (_equippedTitle == itemId) _commit(<String, Object?>{'equippedTitle': null});
      case GardenShopCategory.decor:
        _commit(<String, Object?>{
          'equippedDecor': _equippedDecor.where((id) => id != itemId).toList(),
        });
    }
  }
}
