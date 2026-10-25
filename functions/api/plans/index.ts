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

/** 一次最多提交多少条计划（一学期整张表也就几十条） */
const MAX_ITEMS = 100;

/** week_label 形状：只做宽松字符校验（真正格式由前端定），防止脏值撑爆索引 */
const WEEK_PATTERN = /^[0-9A-Za-z:_-]{1,32}$/;

/** 科目 / 任务名长度上限 */
const SUBJECT_MAX_LENGTH = 40;
const TASK_NAME_MAX_LENGTH = 60;

/** 目标次数上限（防手滑把 target 打成天文数字） */
const MAX_TARGET = 1000;

/** 幂等初始化某周计划：该周已有数据则直接返回，否则按传入模板写入 */
export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  let body: { week_label?: unknown; items?: unknown };
  try {
    body = await request.json<{ week_label?: unknown; items?: unknown }>();
  } catch {
    return Response.json({ error: '请求体不是合法 JSON' }, { status: 400 });
  }

  const { week_label: week, items } = body;
  if (typeof week !== 'string' || !WEEK_PATTERN.test(week)) {
    return Response.json({ error: 'week_label 非法' }, { status: 400 });
  }
  if (!Array.isArray(items) || items.length === 0) {
    return Response.json({ error: 'items 非法' }, { status: 400 });
  }
  if (items.length > MAX_ITEMS) {
    return Response.json({ error: `一次最多提交 ${MAX_ITEMS} 条计划` }, { status: 400 });
  }

  // 先读该周已有条目：既用于「重复提交返回已有列表」的幂等语义，
  // 也避免 INSERT OR IGNORE 撞唯一索引时静默丢条目、接口还回 201。
  const existing = await env.DB.prepare(
    'SELECT subject, task_name FROM weekly_plans WHERE week_label = ?'
  )
    .bind(week)
    .all<{ subject: string; task_name: string }>();
  const seen = new Set(
    (existing.results ?? []).map((row) => `${row.subject}\u0000${row.task_name}`)
  );
  const hadExistingRows = seen.size > 0;

  const now = new Date().toISOString();
  const statements: D1PreparedStatement[] = [];
  for (const raw of items) {
    const item = raw as Record<string, unknown>;
    if (typeof item.subject !== 'string' || typeof item.task_name !== 'string') continue;

    const subject = item.subject.trim().slice(0, SUBJECT_MAX_LENGTH);
    const taskName = item.task_name.trim().slice(0, TASK_NAME_MAX_LENGTH);
    if (!subject || !taskName) continue;

    const dedupeKey = `${subject}\u0000${taskName}`;
    if (seen.has(dedupeKey)) continue;
    seen.add(dedupeKey);

    const rawTarget = Number(item.target);
    const target = Number.isFinite(rawTarget)
      ? Math.min(MAX_TARGET, Math.max(0, Math.round(rawTarget)))
      : 0;

    statements.push(
      env.DB.prepare(
        `INSERT OR IGNORE INTO weekly_plans (id, subject, task_name, target, current, week_label, created_at)
         VALUES (?, ?, ?, ?, 0, ?, ?)`
      ).bind(crypto.randomUUID(), subject, taskName, target, week, now)
    );
  }

  if (statements.length === 0) {
    if (!hadExistingRows) {
      return Response.json({ error: 'items 无有效条目' }, { status: 400 });
    }
    // 该周已经有这些条目：幂等返回现有列表（不是新建）
    const { results } = await env.DB.prepare(
      'SELECT * FROM weekly_plans WHERE week_label = ? ORDER BY rowid ASC'
    )
      .bind(week)
      .all();
    return Response.json(results ?? []);
  }

  await env.DB.batch(statements);

  const { results } = await env.DB.prepare(
    'SELECT * FROM weekly_plans WHERE week_label = ? ORDER BY rowid ASC'
  )
    .bind(week)
    .all();

  return Response.json(results ?? [], { status: 201 });
};
