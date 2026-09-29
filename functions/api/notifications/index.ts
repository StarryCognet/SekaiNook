/**
 * 通知收件箱集合接口。
 * 路由：GET /api/notifications?audience=parent|child&limit=50
 *
 * 说明：通知没有「创建」接口 —— 它们由服务端在记账/审批/结算处写入
 *（见 functions/_lib/notifications.ts）。这里只负责读。
 */

interface Env {
  DB: D1Database;
}

interface NotificationRow {
  id: string;
  audience: string;
  type: string;
  title: string;
  body: string | null;
  link: string | null;
  status: string;
  created_at: string;
  read_at: string | null;
}

const AUDIENCES: readonly string[] = ['parent', 'child'];
const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 200;

/** 读取某一格信箱的通知（按时间倒序）与未读数 */
export const onRequestGet: PagesFunction<Env> = async ({ request, env }) => {
  const search = new URL(request.url).searchParams;
  const audience = search.get('audience');

  if (!audience || !AUDIENCES.includes(audience)) {
    return Response.json({ error: 'audience 非法（应为 parent 或 child）' }, { status: 400 });
  }

  const rawLimit = Number(search.get('limit'));
  const limit = Number.isFinite(rawLimit) && rawLimit > 0
    ? Math.min(Math.floor(rawLimit), MAX_LIMIT)
    : DEFAULT_LIMIT;

  try {
    const [list, unread] = await env.DB.batch<NotificationRow | { unread: number }>([
      env.DB.prepare(
        `SELECT id, audience, type, title, body, link, status, created_at, read_at
           FROM notifications
          WHERE audience = ?
          ORDER BY created_at DESC, rowid DESC
          LIMIT ?`
      ).bind(audience, limit),
      env.DB.prepare(
        `SELECT COUNT(*) AS unread FROM notifications WHERE audience = ? AND status = 'unread'`
      ).bind(audience),
    ]);

    const items = (list.results ?? []) as NotificationRow[];
    const countRow = (unread.results ?? [])[0] as { unread?: number } | undefined;

    return Response.json({ items, unreadCount: countRow?.unread ?? 0, ready: true });
  } catch (error) {
    // 库里还没跑 0003 迁移时不该让前端报错，返回空信箱即可
    console.error('list notifications failed', error);
    return Response.json({ items: [], unreadCount: 0, ready: false });
  }
};
