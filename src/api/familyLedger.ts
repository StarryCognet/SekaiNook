import { ApiError, http } from './http';
import type { LedgerRecord, LedgerStatus, TaskConfig, TaskType } from '../types/family';

/** 花园打卡流水的 task_id 前缀：'garden:' + 任务 / 练习 id */
export const GARDEN_TASK_PREFIX = 'garden:';
/** 花园商城购买的 task_id 前缀：'garden_shop:' + 商品 id */
export const GARDEN_SHOP_PREFIX = 'garden_shop:';
/** 老数据一次性迁移的 task_id：金额由客户端传，服务端夹到 [0, GARDEN_LEGACY_MAX] */
export const GARDEN_LEGACY_TASK_ID = 'garden_legacy';
/** 迁移金额上限：与 functions/_lib/rules.ts 的 GARDEN_LEGACY_MAX 保持一致 */
export const GARDEN_LEGACY_MAX = 2000;

/**
 * 花园阳光的任务 id 前缀：这些流水是花园里的「阳光」，不计入家庭积分。
 * 与 functions/_lib/rules.ts 的 GARDEN_ID_PREFIXES 保持一致。
 */
const GARDEN_ID_PREFIXES: readonly string[] = [
  GARDEN_TASK_PREFIX,
  GARDEN_SHOP_PREFIX,
  GARDEN_LEGACY_TASK_ID,
];

/** 这条流水是不是花园阳光（而不是家庭积分） */
export function isGardenTaskId(taskId: string): boolean {
  return GARDEN_ID_PREFIXES.some((prefix) => taskId.startsWith(prefix));
}

/** 花园打卡流水的 task_id：'garden:' + 任务 / 练习 id（名称与金额由服务端规则决定） */
export function gardenTaskId(id: string): string {
  return `${GARDEN_TASK_PREFIX}${id}`;
}

/** 商城购买的 task_id：'garden_shop:' + 商品 id（价格由服务端规则决定） */
export function gardenShopTaskId(itemId: string): string {
  return `${GARDEN_SHOP_PREFIX}${itemId}`;
}

/** 从 'garden_shop:xxx' 取回商品 id；不是购买流水就返回 null */
export function gardenShopItemId(taskId: string): string | null {
  return taskId.startsWith(GARDEN_SHOP_PREFIX) ? taskId.slice(GARDEN_SHOP_PREFIX.length) : null;
}

/** 生成幂等 id：网络重试 / 离线补发用同一个 id，服务端不会重复入账 */
export function createRequestId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `req-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

/** 查询所有积分流水，按 created_at 倒序（服务端默认只给最近 200 条，别拿它算总余额） */
export async function fetchLedgerRecords(): Promise<LedgerRecord[]> {
  return http.get<LedgerRecord[]>('/api/ledger');
}

/** 全量余额：家庭积分与花园阳光（服务端整表聚合，不受「最近 200 条」窗口限制） */
export interface LedgerSummary {
  family: number;
  sun: number;
}

/** 只认「两个字段都是有限数字」的响应，别把错误页 / 空对象当成余额 0 */
function toSummary(value: unknown): LedgerSummary | null {
  if (!value || typeof value !== 'object') return null;
  const { family, sun } = value as { family?: unknown; sun?: unknown };
  if (typeof family !== 'number' || !Number.isFinite(family)) return null;
  if (typeof sun !== 'number' || !Number.isFinite(sun)) return null;
  return { family, sun };
}

/**
 * 拉全量余额（`GET /api/ledger/summary`，服务端整表聚合，不受「最近 200 条」窗口限制）。
 * 老部署没有这个路由时会抛错，由调用方回退到流水求和 —— 那条路只在过渡期用得到。
 */
export async function fetchLedgerSummary(): Promise<LedgerSummary> {
  const summary = toSummary(await http.get<unknown>('/api/ledger/summary'));
  if (!summary) throw new Error('余额接口返回的格式不对');
  return summary;
}

/** 写一条流水的返回（服务端只回 id / status，不回整条记录） */
export interface LedgerWriteResult {
  id: string;
  status?: LedgerStatus;
  /** true = 这个 id 之前已经入过账（幂等命中），本次没有新增 */
  duplicate?: boolean;
}

/**
 * 写一条流水的底层入口：名称 / 类型 / 金额一律由服务端规则决定，
 * 客户端只给 task_id 与幂等 id（重试必须复用同一个 id，靠服务端主键 INSERT OR IGNORE 去重）。
 * 只有「金额由客户端指定」的历史迁移（garden_legacy）才额外传 amount。
 */
export async function postLedgerRecord(
  taskId: string,
  options: {
    requestId: string;
    amount?: number;
    name?: string;
    type?: TaskType;
    note?: string;
    imageUrl?: string;
  }
): Promise<LedgerWriteResult> {
  return http.post<LedgerWriteResult>(
    '/api/ledger',
    {
      id: options.requestId,
      task_id: taskId,
      task_name: options.name ?? taskId,
      type: options.type ?? 'earning',
      amount: options.amount ?? 0,
      note: options.note ?? null,
      image_url: options.imageUrl ?? null,
    },
    { retry: true }
  );
}

/**
 * 这次写流水是不是「服务端明确拒绝」了（4xx：日限用完、金额非法……）。
 * 这类失败重试多少次都一样：调用方应当出队并回滚乐观值。
 * 网络层失败（status 0）与 5xx / 429 都算「暂时不通」，留在队列里下次再试。
 */
export function isRejectedWriteError(error: unknown): boolean {
  return (
    error instanceof ApiError && error.status >= 400 && error.status < 500 && error.status !== 429
  );
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
  const result = await postLedgerRecord(task.id, {
    requestId: id,
    amount: task.value,
    name: task.name,
    type: task.type,
    note: extra?.note,
    imageUrl: extra?.imageUrl,
  });
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
