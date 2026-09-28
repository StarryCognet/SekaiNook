/**
 * 每周学习计划集合接口。
 * 路由：GET /api/plans?week=<label>、POST /api/plans（幂等初始化某周）
 */

interface Env {
  DB: D1Database;
}

/** 查询某周的学习计划（按插入顺序） */
export const onRequestGet: PagesFunction<Env> = async ({ request, env }) => {
  const week = new URL(request.url).searchParams.get('week');
  if (!week) {
    return Response.json({ error: '缺少 week 参数' }, { status: 400 });
  }

  const { results } = await env.DB.prepare(
    'SELECT * FROM weekly_plans WHERE week_label = ? ORDER BY rowid ASC'
  )
    .bind(week)
    .all();

  return Response.json(results ?? []);
};

/** 幂等初始化某周计划：该周已有数据则直接返回，否则按传入模板写入 */
export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  let body: { week_label?: unknown; items?: unknown };
  try {
    body = await request.json<{ week_label?: unknown; items?: unknown }>();
  } catch {
    return Response.json({ error: '请求体不是合法 JSON' }, { status: 400 });
  }

  const { week_label: week, items } = body;
  if (typeof week !== 'string' || !week) {
    return Response.json({ error: 'week_label 非法' }, { status: 400 });
  }
  if (!Array.isArray(items) || items.length === 0) {
    return Response.json({ error: 'items 非法' }, { status: 400 });
  }

  const now = new Date().toISOString();
  const statements = items
    .map((raw) => raw as Record<string, unknown>)
    .filter((item) => typeof item.subject === 'string' && typeof item.task_name === 'string')
    .map((item) =>
      env.DB.prepare(
        `INSERT OR IGNORE INTO weekly_plans (id, subject, task_name, target, current, week_label, created_at)
         VALUES (?, ?, ?, ?, 0, ?, ?)`
      ).bind(
        crypto.randomUUID(),
        item.subject as string,
        item.task_name as string,
        Number.isFinite(Number(item.target)) ? Number(item.target) : 0,
        week,
        now
      )
    );

  if (statements.length === 0) {
    return Response.json({ error: 'items 无有效条目' }, { status: 400 });
  }
  await env.DB.batch(statements);

  const { results } = await env.DB.prepare(
    'SELECT * FROM weekly_plans WHERE week_label = ? ORDER BY rowid ASC'
  )
    .bind(week)
    .all();

  return Response.json(results ?? [], { status: 201 });
};
