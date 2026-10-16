import '../data/models/ledger_record.dart';
import '../data/models/task_config.dart';

/// 打卡规则的唯一实现（对应 Web 版 `src/utils/taskRules.ts`）。
///
/// 从账本页里抽出来，让账本页与首页（妹妹版）用同一套判断 ——
/// 规则写在两处迟早会写歪（一边让打卡、一边说超限）。

/// 某任务今天已经提交过几次。
///
/// 口径：**含待审批**（孩子提交后家长还没批，也算用掉一次机会）；
/// **不含被驳回**（被驳回的可以改完重新提交，不占名额）。
int countTodaySubmissions(List<LedgerRecord> records, String taskId, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  return records
      .where((record) =>
          record.taskId == taskId &&
          record.status != LedgerStatus.rejected &&
          _isSameLocalDay(record.createdAt, ref))
      .length;
}

/// 同一自然日。两边都是本地时刻（`createdAt` 入库时已 `toLocal()`），
/// 与 Web 版 `toDateString()` 的比较口径一致。
bool _isSameLocalDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 现在能不能打卡；不能则返回给用户看的原因，能则返回 null。
///
/// 检查顺序与 Web 版一致：**先时间窗，再日限**。
String? checkTask(TaskConfig task, List<LedgerRecord> records, {DateTime? now}) {
  final ref = now ?? DateTime.now();

  final window = task.window;
  if (window != null && !window.contains(ref)) {
    return '「${task.name}」只能在 ${window.start}-${window.end} 之间打卡';
  }

  final limit = task.dailyLimit;
  if (limit != null && countTodaySubmissions(records, task.id, now: ref) >= limit) {
    return limit == 1
        ? '「${task.name}」今天已经打过卡啦'
        : '「${task.name}」每天最多 $limit 次，今天用完啦';
  }

  return null;
}

/// 今天的次数是否已经用完（按钮置灰用）。
/// **不限次的任务永远返回 false**。
bool isTaskDone(TaskConfig task, List<LedgerRecord> records, {DateTime? now}) {
  final limit = task.dailyLimit;
  if (limit == null) return false;
  return countTodaySubmissions(records, task.id, now: now) >= limit;
}

/// 今日任务进度
class TaskProgress {
  const TaskProgress({required this.done, required this.total, required this.percent});

  final int done;
  final int total;
  final int percent;
}

/// 今日任务完成度（首页进度条 / 文案用）。
///
/// **只统计有 `dailyLimit` 的任务**：不限次的任务（看 iPad、视力下降…）
/// 不计入分母，否则进度条永远满不了。
TaskProgress todayProgress(List<TaskConfig> tasks, List<LedgerRecord> records, {DateTime? now}) {
  final limited = tasks.where((task) => task.dailyLimit != null).toList();
  final total = limited.length;
  final done = limited.where((task) => isTaskDone(task, records, now: now)).length;
  return TaskProgress(
    done: done,
    total: total,
    percent: total == 0 ? 0 : (done / total * 100).round(),
  );
}
