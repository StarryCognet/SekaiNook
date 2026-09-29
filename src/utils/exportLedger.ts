import type { LedgerRecord } from '../types/family';

/** 流水状态的中文文案（缺省视为已入账，兼容存量数据） */
export function statusText(status: LedgerRecord['status']): string {
  if (status === 'pending') return '待审批';
  if (status === 'rejected') return '已驳回';
  return '已入账';
}

/** CSV 单元格转义：一律加引号，内部引号翻倍 */
function escapeCell(value: string): string {
  return `"${value.replace(/"/g, '""')}"`;
}

/**
 * 导出流水为 CSV 文件（账本页与首页都要用，所以抽出来共用）。
 * 带 BOM，Excel 直接双击打开中文不乱码；返回导出的条数。
 */
export function exportLedgerCsv(records: readonly LedgerRecord[], now = new Date()): number {
  const header = ['时间', '任务', '类型', '积分', '状态', '备注', '图片'];
  const rows = records.map((r) => [
    new Date(r.created_at).toLocaleString('zh-CN'),
    r.task_name,
    r.type === 'earning' ? '赚钱' : '消费/罚款',
    String(r.amount),
    statusText(r.status),
    (r.note ?? '').replace(/[\r\n]+/g, ' '),
    r.image_url ?? '',
  ]);
  const csv = [header, ...rows].map((cells) => cells.map(escapeCell).join(',')).join('\r\n');
  const blob = new Blob([`\uFEFF${csv}`], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = `sekainook-流水-${now.toISOString().slice(0, 10)}.csv`;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
  return rows.length;
}
