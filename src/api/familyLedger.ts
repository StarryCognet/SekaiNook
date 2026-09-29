import { http } from './http';
import type { LedgerRecord, LedgerStatus, TaskConfig } from '../types/family';

/**
 * 花园阳光的任务 id 前缀：这些流水是花园里的「阳光」，不计入家庭积分。
 * 与 functions/_lib/rules.ts 的 GARDEN_ID_PREFIXES 保持一致。
 */
const GARDEN_ID_PREFIXES: readonly string[] = ['garden:', 'garden_shop:', 'garden_legacy'];

/** 这条流水是不是花园阳光（而不是家庭积分） */
export function isGardenTaskId(taskId: string): boolean {
  return GARDEN_ID_PREFIXES.some((prefix) => taskId.startsWith(prefix));
}

/** 生成幂等 id：网络重试 / 离线补发用同一个 id，服务端不会重复入账 */
export function createRequestId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `req-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

/** 查询所有积分流水，按 created_at 倒序（服务端默认只给最近 200 条） */
export async function fetchLedgerRecords(): Promise<LedgerRecord[]> {
  return http.get<LedgerRecord[]>('/api/ledger');
}

/**
 * 插入一条积分流水，金额与任务名以服务端规则为准。
 *
 * 审批状态不再由客户端决定：服务端一律写成 pending（花园奖励等标了 autoApprove 的除外），
 * 只有 PATCH 才能改成 approved。家长自己记的账 / 兑现用 `autoApprove: true`
 * 走「提交 + 立即审批」两步，效果和以前一样，但服务端不再相信客户端的声称。
 *
 * @returns 新记录 id（用于「撤销」等回滚操作）
 */
export async function addLedgerRecord(
  task: TaskConfig,
  extra?: { note?: string; imageUrl?: string; requestId?: string },
  opts?: { autoApprove?: boolean }
): Promise<string> {
  const id = extra?.requestId ?? createRequestId();
  const result = await http.post<{ id: string }>(
    '/api/ledger',
    {
      id,
      task_id: task.id,
      task_name: task.name,
      type: task.type,
      amount: task.value,
      note: extra?.note ?? null,
      image_url: extra?.imageUrl ?? null,
    },
    { retry: true }
  );
  if (opts?.autoApprove && result.id) {
    await updateStatus(result.id, 'approved').catch(() => undefined);
  }
  return result.id;
}

/** 查询待审批的打卡申请，按 created_at 倒序 */
export async function fetchPendingRequests(): Promise<LedgerRecord[]> {
  return http.get<LedgerRecord[]>('/api/ledger?status=pending');
}

/** 修改某条流水的审批状态（reason 只在驳回时有意义，会带给女儿看） */
async function updateStatus(id: string, status: LedgerStatus, reason?: string): Promise<boolean> {
  await http.patch<{ ok: true }>(`/api/ledger/${encodeURIComponent(id)}`, {
    status,
    ...(reason ? { reason } : {}),
  });
  return true;
}

/** 审批通过：状态置为 approved */
export function approveRequest(id: string): Promise<boolean> {
  return updateStatus(id, 'approved');
}

/** 审批驳回：状态置为 rejected，可附一句给女儿的话 */
export function rejectRequest(id: string, reason?: string): Promise<boolean> {
  return updateStatus(id, 'rejected', reason);
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

/** 只统计某类记录里已入账的金额 */
function calcBalance(records: LedgerRecord[], garden: boolean): number {
  return records.reduce(
    (sum, r) =>
      sum +
      ((!r.status || r.status === 'approved') && isGardenTaskId(r.task_id) === garden ? r.amount : 0),
    0
  );
}

/** 计算家庭已入账积分：仅统计无状态（存量）或已审批的记录，且不含花园阳光 */
export function calcApprovedBalance(records: LedgerRecord[]): number {
  return calcBalance(records, false);
}

/** 计算花园阳光余额：只统计花园相关且已入账的记录 */
export function calcGardenBalance(records: LedgerRecord[]): number {
  return calcBalance(records, true);
}
