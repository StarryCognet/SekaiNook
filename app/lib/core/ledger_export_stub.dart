// 没有地方可写文件时的兜底实现：不属于任何已知平台（桌面端本来也不在这份交付里）。
//
// 反馈文案必须和另外两个分支一个口径 —— 它们各自实现同名函数，由
// `ledger_export.dart` 条件导入选一个。

import 'ledger_export_types.dart';

/// 兜底分支没有可写的落点，只能如实报错（调用方会把 `$e` 弹给用户）
Future<LedgerExportResult> saveLedgerCsv(String csv, {String? fileName}) async {
  throw UnsupportedError('这个平台不支持导出文件');
}

/// 兜底分支走不到成功（[saveLedgerCsv] 一律抛），文案只为「万一成功」时留个说法
String ledgerExportToastText(int count, LedgerExportResult result) =>
    '已导出 $count 条流水到 ${result.fileName}';
