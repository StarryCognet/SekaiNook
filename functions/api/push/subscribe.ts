/**
 * Web Push 订阅的登记与退订（订阅信息存 D1，发送由 workers/reminder 的 cron 负责）。
 * 路由：POST   /api/push/subscribe  body: { endpoint, keys: { p256dh, auth }, audience? }
 *       DELETE /api/push/subscribe  body: { endpoint }（取不到时回退 ?endpoint=）
 *
 * 为什么用 endpoint 当唯一键做 UPSERT：同一个浏览器重复订阅（换 SW 版本、点第二次开启）拿到的是
 * 同一个 endpoint，若按「先删后插」处理，中间一步失败就会把本来好用的订阅弄丢；
 * UPSERT 只更新 keys / ua / updated_at，创建时间保持不变。
 * 退订则用 meta.changes 判断是否真删掉了 —— 前端据此区分「已退订」和「这台设备本来就没订阅」。
 */

interface Env {
  DB: D1Database;
}

const AUDIENCES: readonly string[] = ['parent', 'child'];

/** User-Agent 只留个认设备的线索，没必要存全量 */
const MAX_UA_LENGTH = 200;

/** 登记（或更新）一条订阅 */
export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  let body: Record<string, unknown>;
  try {
    body = await request.json<Record<string, unknown>>();
  } catch {
    return Response.json({ error: '请求体不是合法 JSON' }, { status: 400 });
  }

  const { endpoint, keys, audience } = body;

  if (typeof endpoint !== 'string' || !endpoint || !endpoint.startsWith('https://')) {
    return Response.json({ error: 'endpoint 非法（必须是以 https:// 开头的推送端点）' }, { status: 400 });
  }

  if (!keys || typeof keys !== 'object' || Array.isArray(keys)) {
    return Response.json({ error: 'keys 非法（应为 { p256dh, auth }）' }, { status: 400 });
  }

  const { p256dh, auth } = keys as Record<string, unknown>;
  if (typeof p256dh !== 'string' || !p256dh) {
    return Response.json({ error: 'keys.p256dh 非法' }, { status: 400 });
  }
  if (typeof auth !== 'string' || !auth) {
    return Response.json({ error: 'keys.auth 非法' }, { status: 400 });
  }

  // 谁订阅的：缺省当孩子（这个提醒本来就是发给孩子的），只认 parent / child
  const target = audience === undefined ? 'child' : audience;
  if (typeof target !== 'string' || !AUDIENCES.includes(target)) {
    return Response.json({ error: 'audience 非法（应为 parent 或 child）' }, { status: 400 });
  }

  const ua = request.headers.get('user-agent')?.slice(0, MAX_UA_LENGTH) ?? null;
  const now = new Date().toISOString();

  try {
    await env.DB.prepare(
      `INSERT INTO push_subscriptions (endpoint, audience, p256dh, auth, ua, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(endpoint) DO UPDATE SET
          audience = excluded.audience,
          p256dh = excluded.p256dh,
          auth = excluded.auth,
          ua = excluded.ua,
          updated_at = excluded.updated_at`
    )
      .bind(endpoint, target, p256dh, auth, ua, now, now)
      .run();

    return Response.json({ ok: true, endpoint });
  } catch (error) {
    // 常见原因：远端/本地库还没跑 0005 迁移
    console.error('save push subscription failed', error);
    return Response.json({ error: '推送订阅表尚未就绪，请先执行数据库迁移' }, { status: 503 });
  }
};

/** 退订一条订阅（endpoint 从请求体取，取不到回退查询参数） */
export const onRequestDelete: PagesFunction<Env> = async ({ request, env }) => {
  let endpoint = '';

  try {
    const body = await request.json<Record<string, unknown>>();
    if (body && typeof body === 'object' && typeof body.endpoint === 'string') {
      endpoint = body.endpoint.trim();
    }
  } catch {
    // 没请求体 / 不是 JSON 都无所谓：下面还有查询参数这条路
  }

  if (!endpoint) {
    endpoint = new URL(request.url).searchParams.get('endpoint')?.trim() ?? '';
  }

  if (!endpoint) {
    return Response.json({ error: 'endpoint 非法（请求体或 ?endpoint= 至少给一个）' }, { status: 400 });
  }

  try {
    const result = await env.DB.prepare('DELETE FROM push_subscriptions WHERE endpoint = ?').bind(endpoint).run();
    return Response.json({ ok: true, removed: (result.meta.changes ?? 0) > 0 });
  } catch (error) {
    console.error('delete push subscription failed', error);
    return Response.json({ error: '推送订阅表尚未就绪，请先执行数据库迁移' }, { status: 503 });
  }
};
