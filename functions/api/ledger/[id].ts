/**
 * 单条积分流水接口。
 * 路由：PATCH /api/ledger/:id（更新审批状态）、DELETE /api/ledger/:id（删除记录并清理关联图片）
 */

interface Env {
  DB: D1Database;
  STARRYMIKU_BUCKET: R2Bucket;
}

const LEDGER_STATUSES: readonly string[] = ['pending', 'approved', 'rejected'];

/** 从图片 URL（.../api/images/<key>）中还原 R2 对象 key，非法则返回 null */
function extractImageKey(imageUrl: string): string | null {
  const prefix = '/api/images/';
  try {
    const { pathname } = new URL(imageUrl);
    if (!pathname.startsWith(prefix)) return null;
    const key = pathname.slice(prefix.length);
    return key ? decodeURIComponent(key) : null;
  } catch {
    return null;
  }
}

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

/** 删除一条流水，并一并删除其关联的 R2 图片 */
export const onRequestDelete: PagesFunction<Env> = async ({ params, env }) => {
  const id = String(params.id);

  // 先取出记录，拿到图片地址（删除后无法再查）
  const record = await env.DB.prepare('SELECT image_url FROM family_ledger WHERE id = ?')
    .bind(id)
    .first<{ image_url: string | null }>();
  if (!record) {
    return Response.json({ error: '记录不存在' }, { status: 404 });
  }

  // 若含图片，一并删除 R2 中的对象；失败不阻断流水删除
  const key = record.image_url ? extractImageKey(record.image_url) : null;
  if (key) {
    try {
      await env.STARRYMIKU_BUCKET.delete(key);
    } catch {
      // 忽略 R2 删除失败，保证流水仍可删除
    }
  }

  await env.DB.prepare('DELETE FROM family_ledger WHERE id = ?').bind(id).run();
  return Response.json({ ok: true });
};
