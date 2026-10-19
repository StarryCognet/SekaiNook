import '../../core/ledger_ids.dart';
import 'task_config.dart';

/// 流水状态（对应 Web 版 `LedgerStatus`）。
///
/// **注意：接口返回里 status 可能是 null**，null 要当成「已入账」，
/// 不能当成「没有状态所以不算」—— 早期数据没有这个字段。
enum LedgerStatus { pending, approved, rejected }

extension LedgerStatusX on LedgerStatus {
  String get wire => name;

  /// 解析接口返回值；不认识（含 null）时返回 null，由调用方按「已入账」处理
  static LedgerStatus? parse(Object? value) {
    if (value == null) return null;
    for (final item in LedgerStatus.values) {
      if (item.name == value) return item;
    }
    return null;
  }

  /// 界面上显示的中文
  String get label => switch (this) {
        LedgerStatus.pending => '待审批',
        LedgerStatus.approved => '已通过',
        LedgerStatus.rejected => '已驳回',
      };
}

/// 一条流水（对应 Web 版 `LedgerRecord`）。
class LedgerRecord {
  const LedgerRecord({
    required this.id,
    required this.taskId,
    required this.taskName,
    required this.type,
    required this.amount,
    required this.createdAt,
    this.note,
    this.imageUrl,
    this.status,
    this.member,
  });

  final String id;
  final String taskId;
  final String taskName;
  final TaskType type;

  /// 变动分值（earning 为正、spending 为负）
  final int amount;

  /// 记账时间。**已转成本机时区**，直接比较日期即可。
  final DateTime createdAt;
  final String? note;
  final String? imageUrl;

  /// null = 已入账（老数据没有这个字段）
  final LedgerStatus? status;

  /// 历史遗留字段：多成员功能已下线，新写入为空
  final String? member;

  factory LedgerRecord.fromJson(Map<String, dynamic> json) => LedgerRecord(
        id: (json['id'] ?? '') as String,
        taskId: (json['task_id'] ?? '') as String,
        taskName: (json['task_name'] ?? json['task_id'] ?? '') as String,
        type: TaskTypeX.parse(json['type']),
        amount: (json['amount'] as num?)?.toInt() ?? 0,
        createdAt: parseTime(json['created_at']) ?? DateTime.now(),
        note: json['note'] as String?,
        imageUrl: json['image_url'] as String?,
        status: LedgerStatusX.parse(json['status']),
        member: json['member'] as String?,
      );

  /// 解析后端时间戳。后端给的是 UTC ISO 串，这里转本地，页面就不用再操心。
  static DateTime? parseTime(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt()).toLocal();
    }
    return null;
  }

  /// 是否已入账（计入余额）。null 与 approved 都算。
  bool get isCredited => status == null || status == LedgerStatus.approved;

  /// 待审批
  bool get isPending => status == LedgerStatus.pending;

  /// 被驳回（被驳回的不占当天的打卡名额）
  bool get isRejected => status == LedgerStatus.rejected;

  /// 是不是花园流水（花园的阳光/兑换不算家庭余额）
  bool get isGarden => LedgerIds.isGardenTaskId(taskId);

  /// 展示用的正负号文案
  String get signedAmount => amount >= 0 ? '+$amount' : '$amount';

  LedgerRecord copyWith({
    LedgerStatus? status,
    String? note,
    String? imageUrl,
  }) =>
      LedgerRecord(
        id: id,
        taskId: taskId,
        taskName: taskName,
        type: type,
        amount: amount,
        createdAt: createdAt,
        note: note ?? this.note,
        imageUrl: imageUrl ?? this.imageUrl,
        status: status ?? this.status,
        member: member,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'task_id': taskId,
        'task_name': taskName,
        'type': type.wire,
        'amount': amount,
        'created_at': createdAt.toUtc().toIso8601String(),
        if (note != null) 'note': note,
        if (imageUrl != null) 'image_url': imageUrl,
        if (status != null) 'status': status!.wire,
      };
}

/// 记账接口的返回（对应 Web 版 `LedgerWriteResult`）。
class LedgerWriteResult {
  const LedgerWriteResult({required this.id, this.status, this.duplicate});

  final String id;
  final LedgerStatus? status;

  /// 后端判定这条是重复提交（同一个 requestId 已经记过）时为 true
  final bool? duplicate;

  factory LedgerWriteResult.fromJson(Map<String, dynamic> json) => LedgerWriteResult(
        id: (json['id'] ?? '') as String,
        status: LedgerStatusX.parse(json['status']),
        duplicate: json['duplicate'] as bool?,
      );
}

/// 记账成功但审批（PATCH）失败时抛这个（对应 Web 版 `LedgerApprovalError`）。
///
/// 为什么必须让调用方看见：记录其实已经落库、正躺在待审批里，
/// 如果这时静默吞掉，界面就可能谎报「余额已清零」。
class LedgerApprovalException implements Exception {
  const LedgerApprovalException(this.id);

  final String id;

  static const String message = '已记账，但审批没成功 —— 记录在待审批里，去点一下通过';

  @override
  String toString() => 'LedgerApprovalException($id): $message';
}
