/**
 * 自检的公共工具：参数归一化、打接口、断言、时间口径。
 *
 * 为什么把断言做成 helper：五十来条检查项里 90% 是「拿响应 + 比一个值 + 写一句话」，
 * 统一成 ok/fail/warn/skip 之后每条检查只剩几行，读起来就是一份可执行的验收清单。
 */

import { beijingClock, beijingDayBoundsOf } from '../rules';
import type {
  ClientResult,
  SelftestCtx,
  SelftestEnv,
  SelftestOutcome,
  SelftestParams,
} from './types';

/* ---------------------------------- 参数 ---------------------------------- */

function asBool(value: unknown, fallback: boolean): boolean {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') {
    if (value === '0' || value === 'false' || value === '') return false;
    return true;
  }
  if (typeof value === 'number') return value !== 0;
  return fallback;
}

function asInt(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return Math.round(value);
  if (typeof value === 'string' && value.trim() !== '') {
    const n = Number(value);
    if (Number.isFinite(n)) return Math.round(n);
  }
  return null;
}

function asStr(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

const AUDIENCES = ['all', 'parent', 'child'] as const;
const CHANNELS = ['webpush', 'ntfy', 'bark', 'webhook'] as const;

/**
 * 把前端传来的 params 归一化。
 * 非法值一律**回退默认**而不是报错：自检控制台是排查工具，不该因为一个参数打错就整轮跑不动。
 */
export function normalizeParams(raw: unknown, clientResults: ClientResult[] = []): SelftestParams {
  const input = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;

  const nowRaw = asStr(input.now);
  const parsedNow = nowRaw ? new Date(nowRaw) : null;
  const now = parsedNow && !Number.isNaN(parsedNow.getTime()) ? parsedNow : new Date();

  const audienceRaw = asStr(input.audience);
  const channelRaw = asStr(input.channel);
  const priority = asInt(input.priority);

  return {
    dryRun: asBool(input.dryRun, true),
    now,
    simulateDone: asInt(input.simulateDone),
    dayKey: asStr(input.dayKey),
    taskId: asStr(input.taskId) ?? 'clean_room',
    amount: asInt(input.amount) ?? 10,
    note: asStr(input.note) ?? '自检',
    weekLabel: asStr(input.weekLabel),
    audience: AUDIENCES.includes(audienceRaw as (typeof AUDIENCES)[number])
      ? (audienceRaw as SelftestParams['audience'])
      : 'all',
    endpoint: asStr(input.endpoint),
    channel: CHANNELS.includes(channelRaw as (typeof CHANNELS)[number])
      ? (channelRaw as SelftestParams['channel'])
      : null,
    title: asStr(input.title),
    message: asStr(input.message),
    click: asStr(input.click),
    priority: priority !== null && priority >= 1 && priority <= 5 ? priority : null,
    force: asBool(input.force, false),
    keep: asBool(input.keep, false),
    clientResults: new Map(clientResults.map((item) => [item.id, item])),
  };
}

/** 从客户端上报的结果里取某条的数据（口径对账类检查要用） */
export function clientData<T = unknown>(params: SelftestParams, id: string): T | null {
  const item = params.clientResults.get(id);
  if (!item || !item.data) return null;
  return item.data as T;
}

/* ---------------------------------- 时间 ---------------------------------- */

/** 本次自检的「今天」（东八区）。dayKey 参数优先，其次 now，最后真实时间 */
export function dayKeyOf(source: SelftestCtx | SelftestParams): string {
  const params = 'params' in source ? source.params : source;
  return params.dayKey ?? beijingClock(params.now).dayKey;
}

export function boundsOf(dayKey: string): { startIso: string; endIso: string; noonIso: string } {
  return beijingDayBoundsOf(dayKey);
}

/** 东八区「现在」的分钟数（0–1439） */
export function beijingMinutesOf(params: SelftestParams): number {
  return beijingClock(params.now).minutes;
}

/* --------------------------------- 断言工具 -------------------------------- */

export function ok(detail: string, data?: unknown): SelftestOutcome {
  return { status: 'pass', detail, data };
}

export function fail(detail: string, hint?: string, data?: unknown): SelftestOutcome {
  return { status: 'fail', detail, hint, data };
}

export function warn(detail: string, data?: unknown): SelftestOutcome {
  return { status: 'warn', detail, data };
}

export function skip(detail: string): SelftestOutcome {
  return { status: 'skip', detail };
}

/** 写库类检查在预演模式下的统一出口 */
export function previewed(what: string): SelftestOutcome {
  return skip(`预演：${what}（打开「预演」开关才会真写，跑完自清理）`);
}

/* --------------------------------- 打接口 --------------------------------- */

export interface ApiHelpers {
  api: SelftestCtx['api'];
  worker: SelftestCtx['worker'];
}

const DEFAULT_TIMEOUT_MS = 8000;

/** 给 promise 加超时：接口卡住时自检不能一起卡住 */
export async function withTimeout<T>(promise: Promise<T>, ms = DEFAULT_TIMEOUT_MS): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new Error(`超时（${ms}ms）`)), ms);
      }),
    ]);
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}

export function createApiHelpers(env: SelftestEnv, origin: string): ApiHelpers {
  const api = (path: string, init: RequestInit = {}) =>
    fetch(new URL(path, origin).toString(), {
      ...init,
      headers: { Accept: 'application/json', ...(init.headers ?? {}) },
    });

  const worker = (path: string, init: RequestInit = {}) => {
    const base = env.REMINDER_URL?.trim();
    if (!base) throw new Error('未配置 REMINDER_URL（wrangler.jsonc 的 vars）');
    const token = env.REMIND_TOKEN?.trim();
    return fetch(new URL(path, base).toString(), {
      ...init,
      headers: {
        Accept: 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(init.headers ?? {}),
      },
    });
  };

  return { api, worker };
}

/** 读 JSON，读不动就回 null（自检不该因为一个坏响应直接抛） */
export async function readJson<T = unknown>(res: Response): Promise<T | null> {
  try {
    return (await res.json()) as T;
  } catch {
    return null;
  }
}

/** 读文本片段，用于断言页面/脚本内容 */
export async function readText(res: Response, max = 200000): Promise<string> {
  try {
    const text = await res.text();
    return text.length > max ? text.slice(0, max) : text;
  } catch {
    return '';
  }
}

/* --------------------------------- 数据清理 -------------------------------- */

/** 删一条流水（自检自己造的记录一定要删干净） */
export async function deleteLedgerRecord(ctx: SelftestCtx, id: string): Promise<boolean> {
  const res = await ctx.api(`/api/ledger/${encodeURIComponent(id)}`, { method: 'DELETE' });
  return res.ok;
}

/** 生成一个只属于本次自检的 id（幂等检查要一个稳定的、可复现的 id） */
export function selftestId(prefix: string): string {
  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

/** 把长列表截断，避免结果面板被几千条数据撑爆 */
export function head<T>(list: T[], n = 5): T[] {
  return list.slice(0, n);
}

/** 一条流水的最小形状（自检里到处要用） */
export interface LedgerRowLike {
  id: string;
  task_id: string;
  task_name: string;
  type: string;
  amount: number;
  status?: string | null;
  created_at: string;
  image_url?: string | null;
}

/** 取全量流水（多个检查项共用，省一次请求就省一次延迟） */
export async function fetchAllRecords(ctx: SelftestCtx): Promise<LedgerRowLike[]> {
  const res = await ctx.api('/api/ledger');
  const data = await readJson<LedgerRowLike[]>(res);
  return Array.isArray(data) ? data : [];
}
