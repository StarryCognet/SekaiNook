/// ISO 周标签工具（对应 Web 版 `src/utils/week.ts`）。
///
/// 格式：ISO 年 + `-W` + 两位周数，例 `2026-W34`。
/// 必须与后端 SQL `to_char(now(),'IYYY-"W"IW')` 一致 ——
/// **周标签的生成责任在客户端**（拉计划时由前端带上），所以这里算错一天就会读到隔壁周的计划。
abstract final class WeekUtil {
  /// 指定时刻所在周的 ISO 标签；缺省为现在。
  static String isoWeekLabel([DateTime? date]) {
    final d = date ?? DateTime.now();
    // 归一到当天零点，避免时分秒影响跨日计算
    final day = DateTime(d.year, d.month, d.day);

    // ISO 周的定义：包含本周四的那一周；该周四所在年份就是 ISO 年
    final thursday = day.add(Duration(days: DateTime.thursday - day.weekday));
    final year = thursday.year;

    // 该年第一周的周四 = 1 月 4 日所在周的周四
    final jan4 = DateTime(year, 1, 4);
    final firstThursday = jan4.add(Duration(days: DateTime.thursday - jan4.weekday));

    // 用小时数算天数差，避开夏令时导致的 23/25 小时「不足一天」；
    // 再换算成「第几周」——周四之间的天数差除以 7 才是周数差。
    final days = thursday.difference(firstThursday).inHours / 24;
    final week = (days / 7).round() + 1;
    return '$year-W${week.toString().padLeft(2, '0')}';
  }

  /// 当前周标签（语义同 [isoWeekLabel] 无参调用，保留此名以对应 Web 版 `getCurrentWeekLabel`）
  static String currentWeekLabel([DateTime? date]) => isoWeekLabel(date);

  /// 东八区（UTC+8）的「今天」—— 日结算节流的判定基准。
  ///
  /// 用户在手机上可能开着别的时区，但后端按东八区算账，
  /// 所以凡是「哪一天」的判断都要走这里，不能用 `DateTime.now()` 的本地日期。
  static DateTime beijingNow([DateTime? now]) {
    final utc = (now ?? DateTime.now()).toUtc();
    return utc.add(const Duration(hours: 8));
  }

  /// 东八区日期键，形如 `2026-10-14`
  static String beijingDayKey([DateTime? now]) {
    final d = beijingNow(now);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// 同一自然日（比较两边的年月日字段）。
  ///
  /// 调用方要保证两个时刻是**同一种时区口径**：本地时刻比本地时刻、
  /// 东八区比东八区。跨口径比较会得到错误结果（例如本机 UTC 的 `now`
  /// 与东八区时刻比），这时应先用 [beijingNow] 统一。
  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 东八区此刻是几点（0-23）；用于「22 点后」这类判断
  static int beijingHour([DateTime? now]) => beijingNow(now).hour;
}
