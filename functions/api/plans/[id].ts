/**
 * 单条学习计划接口。
 * 路由：PATCH /api/plans/:id（更新当前进度）
 */

interface Env {
  DB: D1Database;
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
  if (typeof current !== 'number' || !Number.isFinite(current) || current < 0) {
    return Response.json({ error: 'current 非法' }, { status: 400 });
  }

  const result = await env.DB.prepare('UPDATE weekly_plans SET current = ? WHERE id = ?')
    .bind(Math.floor(current), id)
    .run();

  if (!result.meta.changes) {
    return Response.json({ error: '记录不存在' }, { status: 404 });
  }
  return Response.json({ ok: true });
};
