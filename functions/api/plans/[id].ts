/**
 * 单条学习计划接口。
 * 路由：PATCH /api/plans/:id（更新当前进度）
 *
 * 写入前把进度收敛到 [0, target]（target = weekly_plans.target，
 * 见 migrations/0001_init.sql:26）。客户端连点或并发覆盖可能送来越界值，
 * 落库前夹一下，避免出现 8/7 这种进度。
 */

interface Env {
  DB: D1Database;
}

/** 把进度收敛到 [0, target]；target 非法（非正数）时只保证下限 0 */
function clampCurrent(value: number, target: number): number {
  const lower = Math.max(0, Math.floor(value));
  if (!Number.isFinite(target) || target <= 0) return lower;
  return Math.min(lower, Math.floor(target));
}

export const onRequestPatch: PagesFunction<Env> = async ({ params, request, env }) => {
  const id = String(params.id);

  let body: { current?: unknown };
  try {
    body = await request.json<{ current?: unknown }>();
  } catch {
    return Response.json({ error: '请求体不是合法 JSON' }, { status: 400 });
  }

  const { current } = body;

  // 先取原行：target 用来收敛；current 用来在入参非法时原样返回（不写库、也不报 500）
  const row = await env.DB.prepare('SELECT target, current FROM weekly_plans WHERE id = ?')
    .bind(id)
    .first<{ target: number | null; current: number | null }>();

  if (!row) {
    return Response.json({ error: '记录不存在' }, { status: 404 });
  }

  if (typeof current !== 'number' || !Number.isFinite(current)) {
    // 非数字 / 缺字段：保持原值，不写库也不报 500
    return Response.json({ ok: true, current: row.current ?? 0 });
  }

  const next = clampCurrent(current, Number(row.target));

  const result = await env.DB.prepare('UPDATE weekly_plans SET current = ? WHERE id = ?')
    .bind(next, id)
    .run();

  if (!result.meta.changes) {
    return Response.json({ error: '记录不存在' }, { status: 404 });
  }
  return Response.json({ ok: true, current: next });
};
