import 'package:flutter_test/flutter_test.dart';
import 'package:sekainook_app/core/week.dart';

/// ISO 周标签是「客户端算、后端查」的约定（后端 SQL 用 `IYYY-"W"IW`），
/// 算错一周就会把隔壁周的学习计划读出来，所以这里把跨年、跨月、
/// 53 周年这些边界钉死。
void main() {
  test('ISO 周标签与后端 to_char(IYYY-"W"IW) 口径一致', () {
    final Map<String, String> cases = <String, String>{
      // 2026-01-01 是周四 —— 它就是 2026 年第 1 周
      '2026-01-01': '2026-W01',
      '2026-01-04': '2026-W01', // 周日，仍属上一 ISO 周
      '2026-01-05': '2026-W02', // 周一开始新的一周
      '2026-10-14': '2026-W42',
      '2026-10-15': '2026-W42',
      '2026-10-18': '2026-W42', // 周日
      '2026-10-19': '2026-W43', // 周一
      // 跨年：2025-12-29（周一）那一周的周四已落在 2026 年
      '2025-12-29': '2026-W01',
      '2025-12-31': '2026-W01',
      // 2026 年有 53 个 ISO 周（因为 1 月 1 日是周四）
      '2026-12-31': '2026-W53',
      '2027-01-01': '2026-W53',
      '2027-01-04': '2027-W01',
      // 反例：年首但属于上一年最后一周
      '2021-01-01': '2020-W53',
    };
    cases.forEach((String day, String expected) {
      final DateTime date = DateTime.parse(day);
      expect(WeekUtil.isoWeekLabel(date), expected, reason: day);
      expect(WeekUtil.currentWeekLabel(date), expected, reason: day);
    });
  });

  test('东八区日期键不受本机时区影响', () {
    // 2026-10-14T20:00Z = 东八区 2026-10-15 04:00
    expect(WeekUtil.beijingDayKey(DateTime.utc(2026, 10, 14, 20)), '2026-10-15');
    // 2026-10-14T15:59Z = 东八区 23:59 同一天
    expect(WeekUtil.beijingDayKey(DateTime.utc(2026, 10, 14, 15, 59)), '2026-10-14');
    expect(WeekUtil.beijingHour(DateTime.utc(2026, 10, 14, 15)), 23);
  });
}
