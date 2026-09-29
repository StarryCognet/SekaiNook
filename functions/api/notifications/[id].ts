/**
 * 单条通知接口。
 * 路由：PATCH /api/notifications/:id（标记已读 / 标回未读）
 */

interface Env {
  DB: D1Database;
}

const STATUSES: readonly string[] = ['read', 'unread'];

/** 更新通知的已读状态 */
export const onRequestPatch: PagesFunction<Env> = async ({ params, request, env }) => {
  const id = String(params.id);

  let body: Record<string, unknown>;
  try {
    body = await request.json<Record<string, unknown>>();
  } catch {
    return Response.json({ error: '请求体不是合法 JSON' }, { status: 400 });
  }

  const { status } = body;
  if (typeof status !== 'string' || !STATUSES.includes(status)) {
    return Response.json({ error: 'status 非法（应为 read 或 unread）' }, { status: 400 });
  }

  const readAt = status === 'read' ? new Date().toISOString() : null;

  try {
    const result = await env.DB.prepare(
      'UPDATE notifications SET status = ?, read_at = ? WHERE id = ?'
    )
      .bind(status, readAt, id)
      .run();

    if (!result.meta.changes) {
      return Response.json({ error: '通知不存在' }, { status: 404 });
    }
    return Response.json({ ok: true });
  } catch (error) {
    console.error('update notification failed', error);
    return Response.json({ error: '通知表尚未就绪，请先执行数据库迁移' }, { status: 503 });
  }
};
