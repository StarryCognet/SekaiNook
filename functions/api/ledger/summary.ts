/**
 * 全量余额接口。
 * 路由：GET /api/ledger/summary → { family: number, sun: number }
 *
 * **为什么单独开一个接口做全表聚合**：`GET /api/ledger` 默认只回最近 200 条
 * （见 functions/api/ledger/index.ts 的 DEFAULT_LIMIT），前端若拿那份窗口数据算余额，
 * 流水一多就会把更早的历史记录漏掉 —— 余额越算越少，这正是要修的旧毛病。
 * 所以这里必须在 SQL 里一次性聚合**整张表**，不设窗口、不分页。
 *
 * 口径（必须与前端 calcApprovedBalance 一致）：
 *   - 只算 `status IS NULL`（历史老数据没有 status）或 `status = 'approved'` 的行，pending / rejected 不计；
 *   - family（家庭积分）/ sun（花园阳光）的划分复用 functions/_lib/rules.ts 的
 *     GARDEN_ID_PREFIXES（经 GARDEN_LIKE_CLAUSE 派生）：**改花园前缀要同步那里**，
 *     本文件不手写字符串，避免出现第三套前缀清单。
 */

import { GARDEN_LIKE_CLAUSE } from '../../_lib/rules';

interface Env {
  DB: D1Database;
}

/** 一条 SQL 同时算出两个余额（导出以便断言脚本直接引用字符串） */
export const LEDGER_SUMMARY_SQL = `SELECT
  SUM(CASE WHEN (${GARDEN_LIKE_CLAUSE}) THEN 0 ELSE amount END) AS family,
  SUM(CASE WHEN (${GARDEN_LIKE_CLAUSE}) THEN amount ELSE 0 END) AS sun
FROM family_ledger
WHERE status IS NULL OR status = 'approved'`;

/** 返回家庭积分与花园阳光的当前余额（全量，不受 200 条窗口限制） */
export const onRequestGet: PagesFunction<Env> = async ({ env }) => {
  try {
    const row = await env.DB.prepare(LEDGER_SUMMARY_SQL).first<{
      family: number | null;
      sun: number | null;
    }>();
    // 空表时 SUM 返回 NULL，归一成数字
    return Response.json({ family: row?.family ?? 0, sun: row?.sun ?? 0 });
  } catch {
    return Response.json({ error: '统计失败' }, { status: 500 });
  }
};
