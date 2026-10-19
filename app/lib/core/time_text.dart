/// 「把时间翻译成人话」的共享工具（对应 Web 版 `src/views/home/homeUtils.ts`）。
///
/// 这几个口径原本在每个用到它的页面里各写了一份私有实现 —— 同一批流水 / 通知，
/// 通知页读作「N 小时前」、首页读作「今天 14:32」，两版之间也对不上。
/// 收敛到这一份之后，改口径只改这里。
///
/// 口径对着 Web 版：`今天 14:32` / `昨天 09:05` / `9月20日 21:10`。
library;

/// `HH:mm`（24 小时制，两位补零）
String clockText(DateTime time) {
  final String hh = time.hour.toString().padLeft(2, '0');
  final String mm = time.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// 本地日历天的键。
///
/// 刻意不用 `toIso8601String()`：那是 UTC 口径，晚上 8 点之后会把今天算成明天。
String _dayKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

/// 相对日期 + 时刻：`今天 14:32` / `昨天 09:05` / `9月20日 21:10`。
///
/// [now] 用来对齐调用方手里那份「会走的现在」—— 页面里有实时时钟时把它传进来，
/// 免得同一屏里两次 `DateTime.now()` 跨过午夜之后自相矛盾。
String relativeDayTime(DateTime at, {DateTime? now}) {
  final DateTime current = now ?? DateTime.now();
  final String time = clockText(at);
  final String day = _dayKey(at);
  if (day == _dayKey(current)) return '今天 $time';
  // 用「本地年月的昨天」而不是减 24 小时：跨月由 Dart 自己进位
  if (day == _dayKey(DateTime(current.year, current.month, current.day - 1))) {
    return '昨天 $time';
  }
  return '${at.month}月${at.day}日 $time';
}
