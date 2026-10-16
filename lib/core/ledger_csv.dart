import '../data/models/ledger_record.dart';
import '../data/models/task_config.dart';

/// 流水导出成 CSV（对应 Web 版 `src/utils/exportLedger.ts`）。
///
/// 家庭账本页与家长版首页共用这一份实现 —— 表头/列序/转义规则写两处迟早写歪。
///
/// 注意：Web 版是「浏览器下载文件」，Flutter 侧（Android 没有下载目录概念，
/// 又不引 share_plus / path_provider）统一改成把这份文本放进剪贴板，
/// 家长粘到表格软件里即可。导出的内容本身与 Web 版同构。
String buildLedgerCsv(List<LedgerRecord> records) {
  final buffer = StringBuffer();
  buffer.write(_csvRow(<String>['时间', '任务', '类型', '积分', '状态', '备注', '图片']));
  for (final record in records) {
    buffer.write('\r\n');
    buffer.write(_csvRow(<String>[
      formatCsvTime(record.createdAt),
      record.taskName,
      record.type == TaskType.earning ? '赚钱' : '消费/罚款',
      '${record.amount}',
      ledgerStatusText(record),
      (record.note ?? '').replaceAll(RegExp('[\r\n]+'), ' '),
      record.imageUrl ?? '',
    ]));
  }
  return buffer.toString();
}

/// CSV 字段转义：整格加引号，内部的引号翻倍
String _csvRow(List<String> cells) =>
    cells.map((cell) => '"${cell.replaceAll('"', '""')}"').join(',');

/// 流水状态的中文文案（缺省视为已入账，兼容存量数据）
String ledgerStatusText(LedgerRecord record) => switch (record.status) {
      LedgerStatus.pending => '待审批',
      LedgerStatus.rejected => '已驳回',
      _ => '已入账',
    };

/// CSV 里的完整时间：`2026-10-15 21:35:04`
String formatCsvTime(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

/// 「导出流水」的统一反馈文案：两种入口说同一句话
String exportToastText(int count) => '已导出 $count 条记录（CSV 已复制到剪贴板）';
