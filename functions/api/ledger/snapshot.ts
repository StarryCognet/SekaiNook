/**
 * 账本快照接口（轮询专用）。
 * 路由：GET /api/ledger/snapshot?limit=200
 * 返回：{ family, sun, pendingCount, pending, records }
 *
 * 为什么要有这个接口：前端多处轮询（主壳 10s 待审批、家庭页 10s/15s、
 * 首页 20s）原本每轮要发三个请求 —— `GET /api/ledger`（流水窗口）、
 * `GET /api/ledger?status=pending`（待审批）、`GET /api/ledger/summary`（全量余额），
 * 三个接口读的其实是同一张表。这里用一次 `DB.batch`（D1 在同一次往返里并发执行）
 * 把它们合成一个响应，前端一轮轮询 = 一个请求。
 *
 * 口径与各自单接口保持一致：
 *   - records：最近 limit 条，按 created_at 倒序（同 `GET /api/ledger`）
 *   - pending：status = 'pending' 的整份列表（同 `GET /api/ledger?status=pending`）
 *   - family / sun：全表聚合（同 `/api/ledger/summary`，SQL 直接复用）
 *
 * 注意：这里的 `pendingCount` 取的是 pending 列表长度 —— 与前端角标同源，
 * 保证「红点数字」和「点进去看到的条数」永远一致。
 */

import { LEDGER_SUMMARY_SQL } from './summary';

interface Env {
  DB: D1Database;
}

/** 与 functions/api/ledger/index.ts 的 DEFAULT_LIMIT 保持一致 */
const DEFAULT_LIMIT = 200;
const MAX_LIMIT = 500;

interface LedgerRow {
  id: string;
  task_id: string;
  task_name: string;
  type: string;
  amount: number;
  note: string | null;
  image_url: string | null;
  status: string | null;
  created_at: string;
  member?: string | null;
}

interface SummaryRow {
  family: number | null;
  sun: number | null;
}

export const onRequestGet: PagesFunction<Env> = async ({ request, env }) => {
  const search = new URL(request.url).searchParams;
  const limitRaw = Number(search.get('limit'));
  const limit =
    Number.isFinite(limitRaw) && limitRaw > 0
      ? Math.min(Math.floor(limitRaw), MAX_LIMIT)
      : DEFAULT_LIMIT;

  try {
    // 一次 batch：三个 SELECT 在同一次往返里取回，省两次网络往返
    // LIMIT 用插值而不是绑定参数 —— 与 functions/api/ledger/index.ts 的写法一致，
    // 且 limit 已夹在 [1, MAX_LIMIT]，不可能注入。
    const [recordsResult, pendingResult, summaryResult] = await env.DB.batch<
      LedgerRow | SummaryRow
    >([
      env.DB.prepare(
        `SELECT * FROM family_ledger ORDER BY created_at DESC LIMIT ${limit}`
      ),
      env.DB.prepare(
        `SELECT * FROM family_ledger WHERE status = 'pending' ORDER BY created_at DESC LIMIT ${limit}`
      ),
      env.DB.prepare(LEDGER_SUMMARY_SQL),
    ]);

    const records = (recordsResult.results ?? []) as LedgerRow[];
    const pending = (pendingResult.results ?? []) as LedgerRow[];
    const summary = (summaryResult.results ?? [])[0] as SummaryRow | undefined;

    return Response.json({
      family: summary?.family ?? 0,
      sun: summary?.sun ?? 0,
      pendingCount: pending.length,
      pending,
      records,
    });
  } catch (error) {
    console.error('ledger snapshot failed', error);
    return Response.json({ error: '统计失败' }, { status: 500 });
  }
};
