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
/** 日结算接口（v1.30 需求 2 / 7）：服务端按幂等 id 补记罚款，重复调用安全 */
export const LEDGER_SETTLE_PATH = '/api/ledger/settle';

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

/** 日结算结果 */
export interface LedgerSettleResult {
  /** 结算后的家庭积分余额 */
  family: number;
  /** 结算后的花园阳光余额 */
  sun: number;
  /** 本次实际入账了哪几条（服务端幂等 id，重复调用会是空数组） */
  applied: string[];
  /** **被结算的那一天**（东八区 YYYY-MM-DD）—— 可能不是今天，节流键要存这个值 */
  day: string;
}

/** 只认字段齐全的结算响应，别把错误页 / 空对象当成「结算过了」 */
function toSettleResult(value: unknown): LedgerSettleResult | null {
  if (!value || typeof value !== 'object') return null;
  const { family, sun, applied, day } = value as {
    family?: unknown;
    sun?: unknown;
    applied?: unknown;
    day?: unknown;
  };
  if (typeof family !== 'number' || !Number.isFinite(family)) return null;
  if (typeof sun !== 'number' || !Number.isFinite(sun)) return null;
  if (typeof day !== 'string' || day === '') return null;
  if (!Array.isArray(applied) || !applied.every((x): x is string => typeof x === 'string')) {
    return null;
  }
  return { family, sun, applied, day };
}

/**
 * 触发一次日结算（`POST /api/ledger/settle`，请求体可空）。
 *
 * 正确性完全由服务端幂等 id 保证（开户礼金 / 每日不足 5 个任务 / 睡觉罚款），
 * 所以这里**失败一律静默返回 null** —— 结算失败绝不能挡住页面。
 * 调用方的本地节流只为省流量，不得当成防重复扣的手段。
 */
export async function settleLedger(): Promise<LedgerSettleResult | null> {
  try {
    return toSettleResult(await http.post<unknown>(LEDGER_SETTLE_PATH, {}));
  } catch {
    return null;
  }
}

/** 本地结算节流键（存的是「被结算的那一天」，不是调用当天） */
export const LEDGER_SETTLE_DAY_KEY = 'sekainook_settle_day';

const BEIJING_OFFSET_MS = 8 * 60 * 60 * 1000;

/**
 * 本地推算「本次会被结算的那一天」，与服务端 settleDay 同规则：
 * 东八区 ≥22:00 记今天，否则记昨天。**只用于节流**，不作为任何正确性依据。
 */
function expectedSettleDay(now: Date): string {
  const shifted = new Date(now.getTime() + BEIJING_OFFSET_MS);
  if (shifted.getUTCHours() < 22) shifted.setUTCDate(shifted.getUTCDate() - 1);
  return shifted.toISOString().slice(0, 10);
}

/**
 * 按「被结算的那一天」节流地触发一次结算：同一天已经结算过就不再发请求。
 *
 * ⚠️ 正确性完全由服务端幂等 id 保证（`daily_penalty_<day>` / `sleep_penalty_<day>`），
 * 这里的节流纯粹为了省流量，**任何情况下都不能当成防重复扣的手段**
 * —— 节流记录丢了最多多发一次请求，服务端会认出重复。
 *
 * @returns 服务端响应；`null` 表示「这一天已经结算过」或「请求失败」，两种都不该挡住页面
 */
export async function settleLedgerOncePerDay(
  now: Date = new Date()
): Promise<LedgerSettleResult | null> {
  const expected = expectedSettleDay(now);
  try {
    if (localStorage.getItem(LEDGER_SETTLE_DAY_KEY) === expected) return null;
  } catch {
    // 读不到就当没结算过：多发一次请求，服务端幂等，安全
  }
  const result = await settleLedger();
  if (result) {
    try {
      localStorage.setItem(LEDGER_SETTLE_DAY_KEY, result.day);
    } catch {
      // 存不进去也不影响这一次
    }
  }
  return result;
}

/** 把结算入账的 id 说成人话（罚款要说清原因，别甩一串英文 id 给孩子看） */
export function describeSettleApplied(ids: readonly string[]): string {
  return ids
    .map((id) => {
      if (id.startsWith('seed_welcome_bonus')) return '开户礼金 +100';
      if (id.startsWith('sleep_penalty')) return '到 22:00 还没打卡睡觉 -20';
      if (id.startsWith('daily_penalty') || id.startsWith('daily_min_tasks_penalty')) {
        return '那天完成的任务不够 5 个 -10';
      }
      if (id.startsWith('sleep_on_time')) return '按时打卡睡觉 +10';
      return id;
    })
    .join('；');
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
 * 「记账成功、但立即审批那一步失败」时抛出的错误。
 *
 * 兑现 / 家长自己记账走的是两步：先 POST 记账，再 PATCH 审批。第二步失败如果静默吞掉，
 * 调用方就会报「已兑现 X 积分，余额清零」—— 而服务端余额只统计无状态或 approved 的流水
 * （functions/api/ledger/summary.ts），这笔钱其实没清零，记录以 pending 躺在待审批里。
 * 所以这里必须让调用方看得见：带上 id，调用方据此提示「去待审批里点通过」并重新拉账本。
 */
export class LedgerApprovalError extends Error {
  /** 已经记上的那条流水 id */
  readonly id: string;

  constructor(id: string) {
    super('已记账，但审批没成功 —— 记录在待审批里，去点一下通过');
    this.name = 'LedgerApprovalError';
    this.id = id;
  }
}

/**
 * 插入一条积分流水，金额与任务名以服务端规则为准。
 *
 * 审批状态不再由客户端决定：服务端一律写成 pending（花园奖励等标了 autoApprove 的除外），
 * 只有 PATCH 才能改成 approved。家长自己记的账 / 兑现用 `autoApprove: true`
 * 走「提交 + 立即审批」两步，效果和以前一样，但服务端不再相信客户端的声称。
 *
 * @returns 新记录 id（用于「撤销」等回滚操作）
 * @throws {LedgerApprovalError} 记账成功但审批失败：钱还挂在余额上，记录在待审批里
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
    try {
      await updateStatus(result.id, 'approved');
    } catch {
      // 不能吞：账已经记上了，调用方若照常报「余额清零」就是在骗人
      throw new LedgerApprovalError(result.id);
    }
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
