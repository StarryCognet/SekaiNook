/**
 * 单条积分流水接口。
 * 路由：PATCH /api/ledger/:id（更新审批状态）、DELETE /api/ledger/:id
 */

interface Env {
  DB: D1Database;
}

const LEDGER_STATUSES: readonly string[] = ['pending', 'approved', 'rejected'];

/** 更新审批状态（审批通过 / 驳回 / 重新提交） */
export const onRequestPatch: PagesFunction<Env> = async ({ params, request, env }) => {
  const id = String(params.id);

  let body: Record<string, unknown>;
  try {
    body = await request.json<Record<string, unknown>>();
  } catch {
    return Response.json({ error: '请求体不是合法 JSON' }, { status: 400 });
  }

  const { status } = body;
  if (typeof status !== 'string' || !LEDGER_STATUSES.includes(status)) {
    return Response.json({ error: 'status 非法' }, { status: 400 });
  }

  const result = await env.DB.prepare('UPDATE family_ledger SET status = ? WHERE id = ?')
    .bind(status, id)
    .run();

  if (!result.meta.changes) {
    return Response.json({ error: '记录不存在' }, { status: 404 });
  }
  return Response.json({ ok: true });
};

/** 删除一条流水 */
export const onRequestDelete: PagesFunction<Env> = async ({ params, env }) => {
  const id = String(params.id);

  const result = await env.DB.prepare('DELETE FROM family_ledger WHERE id = ?').bind(id).run();
  if (!result.meta.changes) {
    return Response.json({ error: '记录不存在' }, { status: 404 });
  }
  return Response.json({ ok: true });
};
