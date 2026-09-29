/**
 * 整格信箱一键已读。
 * 路由：POST /api/notifications/read-all  body: { audience: 'parent' | 'child' }
 */

interface Env {
  DB: D1Database;
}

const AUDIENCES: readonly string[] = ['parent', 'child'];

/** 把某一格信箱里的未读通知全部标记为已读 */
export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  let body: Record<string, unknown>;
  try {
    body = await request.json<Record<string, unknown>>();
  } catch {
    return Response.json({ error: '请求体不是合法 JSON' }, { status: 400 });
  }

  const { audience } = body;
  if (typeof audience !== 'string' || !AUDIENCES.includes(audience)) {
    return Response.json({ error: 'audience 非法（应为 parent 或 child）' }, { status: 400 });
  }

  try {
    const result = await env.DB.prepare(
      `UPDATE notifications SET status = 'read', read_at = ?
        WHERE audience = ? AND status = 'unread'`
    )
      .bind(new Date().toISOString(), audience)
      .run();

    return Response.json({ ok: true, updated: result.meta.changes ?? 0 });
  } catch (error) {
    console.error('mark all read failed', error);
    return Response.json({ error: '通知表尚未就绪，请先执行数据库迁移' }, { status: 503 });
  }
};
