import { http } from './http';
import type { LedgerRecord, LedgerStatus, TaskConfig } from '../types/family';

/** 查询所有积分流水，按 created_at 倒序 */
export async function fetchLedgerRecords(): Promise<LedgerRecord[]> {
  return http.get<LedgerRecord[]>('/api/ledger');
}

/**
 * 插入一条积分流水，amount 取 task.value，可附带备注、图片、成员与审批状态。
 * @returns 新记录 id（用于「撤销」等回滚操作）
 */
export async function addLedgerRecord(
  task: TaskConfig,
  extra?: { note?: string; imageUrl?: string; member?: string | null },
  opts?: { status?: LedgerStatus }
): Promise<string> {
  const result = await http.post<{ id: string }>('/api/ledger', {
    task_id: task.id,
    task_name: task.name,
    type: task.type,
    amount: task.value,
    note: extra?.note ?? null,
    image_url: extra?.imageUrl ?? null,
    member: extra?.member ?? null,
    status: opts?.status ?? 'approved',
  });
  return result.id;
}

/** 查询待审批的打卡申请，按 created_at 倒序 */
export async function fetchPendingRequests(): Promise<LedgerRecord[]> {
  return http.get<LedgerRecord[]>('/api/ledger?status=pending');
}

/** 修改某条流水的审批状态 */
async function updateStatus(id: string, status: LedgerStatus): Promise<boolean> {
  await http.patch<{ ok: true }>(`/api/ledger/${encodeURIComponent(id)}`, { status });
  return true;
}

/** 审批通过：状态置为 approved */
export function approveRequest(id: string): Promise<boolean> {
  return updateStatus(id, 'approved');
}

/** 审批驳回：状态置为 rejected */
export function rejectRequest(id: string): Promise<boolean> {
  return updateStatus(id, 'rejected');
}

/** 驳回后重新提交：状态置回 pending */
export function resubmitRequest(id: string): Promise<boolean> {
  return updateStatus(id, 'pending');
}

/** 删除一条流水（仅家长）；若含图片，后端会一并删除 R2 中的图片 */
export async function deleteLedgerRecord(id: string): Promise<boolean> {
  await http.delete<{ ok: true }>(`/api/ledger/${encodeURIComponent(id)}`);
  return true;
}

/** 计算已入账余额：仅统计无状态（存量）或已审批的记录 */
export function calcApprovedBalance(records: LedgerRecord[]): number {
  return records.reduce(
    (sum, r) => sum + (!r.status || r.status === 'approved' ? r.amount : 0),
    0
  );
}
