import '../config/family_rules.dart';
import '../data/models/ledger_record.dart';
import '../data/models/task_config.dart';
import 'week.dart';

/// 「今天算完成了几个任务」的客户端口径 —— 必须与服务端一致。
///
/// 服务端口径在 `functions/_lib/rules.ts` 的 `DAY_COMPLETION_SQL`：
/// 东八区当日、`status IS NULL OR status='approved'`（**待审批也算完成**）、
/// `type='earning' AND amount>0`、排除三个系统 id、**按 task_id 去重**
/// （一天背三首诗只算 1 个任务）。
///
/// 首页那个 `todayProgress`（[TaskProgress]）**不能用**：它按设备本地时区、
/// 分母是「有日限的任务数」，与服务端的「按 task_id 去重的 earning 条数」不同。
/// 本地提醒要说「还差几个」，说错了比不说更糟，所以这里单独实现一份。

/// 不参与「完成几个任务」统计的系统流水 id（与服务端 `COMPLETION_EXCLUDED_IDS` 一致）
const Set<String> kCompletionExcludedIds = {
  'seed_welcome_bonus',
  'daily_min_tasks_penalty',
  'sleep_penalty',
};

/// 当天完成任务数（按 task_id 去重）
class DayCompletion {
  const DayCompletion({
    required this.dayKey,
    required this.done,
    required this.target,
  });

  /// 东八区日期键，形如 `2026-10-17`
  final String dayKey;

  /// 已完成的**不同任务**数
  final int done;

  /// 目标数（服务端 `DAILY_MIN_TASKS`）
  final int target;

  /// 还差几个；已完成时是 0
  int get remaining => done >= target ? 0 : target - done;

  /// 今天是否已达标
  bool get isComplete => done >= target;
}

/// 数一数今天完成了几个任务（东八区口径，与服务端一致）
DayCompletion countDayCompletions(List<LedgerRecord> records, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final dayKey = WeekUtil.beijingDayKey(ref);

  // 东八区当日的 [00:00, 次日 00:00) 对应到 UTC 瞬间
  final beijing = WeekUtil.beijingNow(ref);
  final startUtc = DateTime.utc(beijing.year, beijing.month, beijing.day)
      .subtract(const Duration(hours: 8));
  final endUtc = startUtc.add(const Duration(days: 1));

  final ids = <String>{};
  for (final record in records) {
    if (record.status != null && record.status != LedgerStatus.approved) continue;
    if (record.type != TaskType.earning || record.amount <= 0) continue;
    if (kCompletionExcludedIds.contains(record.taskId)) continue;

    final at = record.createdAt.toUtc();
    if (at.isBefore(startUtc) || !at.isBefore(endUtc)) continue;

    ids.add(record.taskId);
  }

  return DayCompletion(
    dayKey: dayKey,
    done: ids.length,
    target: FamilyRules.dailyMinTasks,
  );
}

/// 本地提醒的文案。与服务端 Worker 发出来的话保持一致，
/// 免得孩子手机上两条提醒（网站推送 + App 本地）说法不一样。
class ReminderText {
  const ReminderText({required this.title, required this.body});

  final String title;
  final String body;

  /// 「今天已经做完了」时没有提醒可言
  static const ReminderText allDone = ReminderText(
    title: '今天的任务已经做完了',
    body: '5 个任务都打上卡了，早点休息。',
  );

  /// 还没打开过 App、不知道今天做了几个时的通用文案
  static const ReminderText unknown = ReminderText(
    title: '今天的任务做完了吗',
    body: '22:00 前要做完 5 个任务，不然要扣 10 分。',
  );
}

/// 按完成数生成提醒文案（口径与服务端 `planReminder` 一致）
ReminderText reminderTextFor(DayCompletion completion) {
  if (completion.isComplete) return ReminderText.allDone;

  final penalty = FamilyRules.dailyMinTasksPenalty.abs();
  final sleepPenalty = FamilyRules.sleepPenaltyAmount.abs();
  return ReminderText(
    title: '今天还差 ${completion.remaining} 个任务',
    body: '已完成 ${completion.done}/${completion.target} —— 22:00 前做完，不然扣 $penalty 分。\n'
        '睡觉卡也别忘了：晚于 22:00 打卡要扣 $sleepPenalty 分。',
  );
}
