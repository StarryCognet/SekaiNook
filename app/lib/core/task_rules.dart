import '../data/models/ledger_record.dart';
import '../data/models/task_config.dart';
import 'week.dart';

/// 打卡规则的唯一实现（对应 Web 版 `src/utils/taskRules.ts`）。
///
/// 从账本页里抽出来，让账本页与首页（妹妹版）用同一套判断 ——
/// 规则写在两处迟早会写歪（一边让打卡、一边说超限）。

/// 提交这条任务是否必须带一张照片（拍照 / 相册）。
///
/// 规则：任务自己声明了 `requirePhoto` 就听它的（自定义任务就是这么定的），
/// 否则按类型兜底 —— **赚钱类必须，消费与罚款不强制**。
/// 全站只有这一处判断：打卡弹窗的按钮置灰与提交前的兜底校验、
/// 家长端「添加任务」表单的默认值都从这里取，免得两边说法不一致。
bool taskRequiresPhoto(TaskConfig task) {
  final bool? declared = task.requirePhoto;
  if (declared != null) return declared;
  return task.type == TaskType.earning;
}

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

/// 今天各任务的提交次数（一次扫完账本）。
///
/// 任务区要按「这个任务还能不能做」逐个判断，逐个调 [countTodaySubmissions]
/// 是 O(任务数 × 流水数)；页面只要重建就会重跑，所以先归并成一张表。
/// 口径与 [countTodaySubmissions] 完全一致。
Map<String, int> countTodaySubmissionsByTask(List<LedgerRecord> records, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final counts = <String, int>{};
  for (final record in records) {
    final taskId = record.taskId;
    if (taskId.isEmpty) continue;
    if (record.status == LedgerStatus.rejected) continue;
    if (!_isSameLocalDay(record.createdAt, ref)) continue;
    counts[taskId] = (counts[taskId] ?? 0) + 1;
  }
  return counts;
}

/// 同一自然日。两边都是本地时刻（`createdAt` 入库时已 `toLocal()`），
/// 与 Web 版 `toDateString()` 的比较口径一致。
bool _isSameLocalDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 本周（周一 00:00 起）某任务已经提交过几次。
///
/// 口径与 [countTodaySubmissions] 一致（含待审批、不含被驳回）。
/// 周任务（洗头一周 3 次 / 剪指甲一周 1 次）要显示「本周 1/3 次」和三个小圆点，
/// 所以按**自然周（周一–周日）**数 —— 与服务端日结算的周口径对齐，
/// 否则前端显示「做满了」而后端还在扣缺次罚款。
int countWeekSubmissions(List<LedgerRecord> records, String taskId, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final weekStart = _startOfWeek(ref);
  return records
      .where((record) =>
          record.taskId == taskId &&
          record.status != LedgerStatus.rejected &&
          !record.createdAt.isBefore(weekStart) &&
          !record.createdAt.isAfter(ref))
      .length;
}

/// 某一刻所在自然周的起点（东八区周一 00:00 对应的**真实时刻**）。
///
/// 后端按东八区结算周（与 [WeekUtil.beijingNow] 同口径），而 `createdAt` 是
/// 真实瞬间。所以先取东八区墙钟上「本周一 00:00」，再减 8 小时还原成 UTC
/// 时刻 —— 非东八区设备上也不会与后端缺次罚款口径错位。
DateTime _startOfWeek(DateTime moment) {
  final beijing = WeekUtil.beijingNow(moment);
  // 东八区墙钟的当日零点（以 UTC 标记承载，避免本机时区参与构造）
  final day = DateTime.utc(beijing.year, beijing.month, beijing.day);
  final mondayWall = day.subtract(Duration(days: day.weekday - DateTime.monday));
  return mondayWall.subtract(const Duration(hours: 8));
}

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
/// **只统计「日常」组里有 `dailyLimit` 的任务**：
/// - 不限次的任务（看 iPad、视力下降…）不计入分母，否则进度条永远满不了；
/// - 周任务（洗头 3 次 / 剪指甲 / 上班）与特殊加分（参赛获奖）也不进分母 ——
///   它们按自然周结算或压根不限次，混进「今天 2/15」会让人以为今天要干 15 件事。
TaskProgress todayProgress(List<TaskConfig> tasks, List<LedgerRecord> records, {DateTime? now}) {
  final limited = tasks
      .where((task) => task.dailyLimit != null && task.group == TaskGroup.daily)
      .toList();
  final total = limited.length;
  // 先聚合一次再查表（M-12）：以前对每个任务调 isTaskDone，
  // 每个任务都全表扫一遍，任务一多就是 O(任务数 × 流水数)。
  final Map<String, int> counts = countTodaySubmissionsByTask(records, now: now);
  var done = 0;
  for (final task in limited) {
    final limit = task.dailyLimit;
    if (limit != null && (counts[task.id] ?? 0) >= limit) done++;
  }
  return TaskProgress(
    done: done,
    total: total,
    percent: total == 0 ? 0 : (done / total * 100).round(),
  );
}
