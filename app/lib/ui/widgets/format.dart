/// 全站统一的数字 / 金额 / 日期展示格式。
///
/// 之前余额、积分、日期各写各的（裸数字、MM-dd / MM/dd / yyyy-MM-dd 三套），
/// 本文件是唯一入口。新增展示格式请加在这里，不要散落到页面里。
library;

String _groupInteger(String digits) {
  if (digits.length <= 3) return digits;
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;
    buffer.write(digits[i]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
  }
  return buffer.toString();
}

/// `1095` → `1,095`。负数保留符号。
String formatCount(num value) {
  final rounded = value.round();
  final negative = rounded < 0;
  final text = _groupInteger(rounded.abs().toString());
  return negative ? '-$text' : text;
}

/// 积分/阳光等整数计数。
String formatPoints(num value) => formatCount(value);

/// `1234.5` → `1,234.50`（金额保留两位）。
String formatYuan(num value) {
  final negative = value < 0;
  final parts = value.abs().toStringAsFixed(2).split('.');
  final text = '${_groupInteger(parts[0])}.${parts[1]}';
  return negative ? '-$text' : text;
}

/// 统一日期时间：`2026-10-25 14:30`；今天/昨天用相对说法。
String formatDateTime(DateTime time, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(time.year, time.month, time.day);
  final hm =
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  if (day == today) return '今天 $hm';
  if (day == today.subtract(const Duration(days: 1))) return '昨天 $hm';
  final sameYear = time.year == current.year;
  final md = '${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';
  return sameYear ? '$md $hm' : '${time.year}-$md $hm';
}
