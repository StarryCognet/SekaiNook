// 「导出流水」两个平台分支共用的那份东西：结果类型、文件名拼法、成功文案。
//
// 单独一个文件是为了避开「外壳 ↔ 分支」互相 import 的圈：外壳
// （`ledger_export.dart`）条件导入三个分支，分支反过来要结果类型，只好放在第三处。
//
// **文件名拼法只写一遍**，三个分支（io / web / stub）都调这里 —— 三处各写一份迟早写歪。

/// 一次导出的落点：调用方据此组织提示文案。
///
/// 两个平台问的是同一件事，答案却不一样：安卓能说清「文件在哪个目录」，
/// Web 只能说「下载已经开始了」（落盘到哪个文件夹由浏览器说了算，Dart 侧看不见）。
class LedgerExportResult {
  const LedgerExportResult({required this.fileName, this.location, this.path});

  /// 文件名，如 `sekainook-流水-2026-10-19.csv`
  final String fileName;

  /// 落点的人话说法。安卓/iOS 上是「分享」（落点由用户在分享面板里挑），
  /// Web 上为 null —— 下载落到哪个文件夹由浏览器说了算，Dart 侧看不见。
  final String? location;

  /// 本机绝对路径。Web 上为 null。
  final String? path;
}

/// CSV 的文件名（对应 Web 版的 `sekainook-流水-YYYY-MM-DD.csv`）。
///
/// 用本地日期（Web 版那边取的是 `toISOString()`，即 UTC）：文件名要和 CSV 里的
/// 流水时间（本地）对得上，晚上 8 点以后导出的那份才不会写着「明天」。
///
/// [date] 只给测试用。取 `toIso8601String()` 前 10 位就是 `YYYY-MM-DD`，
/// 等价于 Web 版的 `toISOString().slice(0, 10)`，省掉一个 intl 依赖。
String ledgerExportFileName(DateTime date) {
  final String local = date.toLocal().toIso8601String();
  return 'sekainook-流水-${local.substring(0, 10)}.csv';
}
