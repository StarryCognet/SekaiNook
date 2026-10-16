/// 每周学习计划的一条（对应 Web 版 `src/types/family.ts` 的 `WeeklyPlan`）。
///
/// 服务端表是 `weekly_plans`，唯一约束 `UNIQUE(week_label, task_name)`，
/// 所以「初始化某周」是幂等的（`INSERT OR IGNORE`）。
class WeeklyPlan {
  const WeeklyPlan({
    required this.id,
    required this.subject,
    required this.taskName,
    required this.target,
    required this.current,
    required this.weekLabel,
    this.createdAt,
  });

  final String id;

  /// 学科：英语 / 语文 / 数学 / 日常
  final String subject;
  final String taskName;

  /// 目标值
  final int target;

  /// 当前进度（服务端会夹到 `[0, target]`）
  final int current;
  final String weekLabel;
  final DateTime? createdAt;

  factory WeeklyPlan.fromJson(Map<String, dynamic> json) => WeeklyPlan(
        id: (json['id'] ?? '') as String,
        subject: (json['subject'] ?? '') as String,
        taskName: (json['task_name'] ?? '') as String,
        target: (json['target'] as num?)?.round() ?? 0,
        current: (json['current'] as num?)?.round() ?? 0,
        weekLabel: (json['week_label'] ?? '') as String,
        createdAt: DateTime.tryParse((json['created_at'] as String?) ?? '')?.toLocal(),
      );

  /// 进度百分比（0-100）。目标为 0 时按 0 处理，避免除零。
  int get percent {
    if (target <= 0) return 0;
    final value = (current / target * 100).round();
    return value < 0 ? 0 : (value > 100 ? 100 : value);
  }

  WeeklyPlan copyWith({int? current}) => WeeklyPlan(
        id: id,
        subject: subject,
        taskName: taskName,
        target: target,
        current: current ?? this.current,
        weekLabel: weekLabel,
        createdAt: createdAt,
      );
}
