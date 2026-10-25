/**
 * 手机提醒的「发一条测试通知」。
 * 路由：POST /api/push/test  body: { audience?: 'parent' | 'child' }
 *
 * 为什么由 Pages 代打而不是前端直接调 Worker：真发推送的 Worker 要带 REMIND_TOKEN，
 * 那是服务端密钥，下发到浏览器等于把「给全家手机发通知」的能力公开。
 * 这里让 Pages 用令牌转一手，前端只拿到「发了几台设备」这种结果。
 *
 * 为什么不要管理员密码：手机提醒这个区块是给孩子用的（他自己的手机要能当场试一下通不通），
 * 而管理员密码在妈妈手里。这条接口只能给「已经订阅过的设备」发一条固定文案，
 * 既改不了数据也删不了东西，所以用冷却时间防连点即可，不引入密码门禁。
 *
 * 为什么冷却 15 秒：不然连点几下就是给全家手机刷屏，而且推送服务商会把这些当异常流量。
 * 标记写在 settings 表（跟 reminder_sent_<day> 同一张表），过期即失效，不需要清理任务。
 */

interface Env {
  DB: D1Database;
  /** 提醒 Worker 的地址（Pages 环境变量，例如 https://sekainook-reminder.xxx.workers.dev） */
  REMINDER_URL?: string;
  /** 调用提醒 Worker 的令牌（Pages secret，与 Worker 的 REMIND_TOKEN 同一份） */
  REMIND_TOKEN?: string;
}

const AUDIENCES: readonly string[] = ['parent', 'child'];

/** 同一个人两次点「测试」之间的最短间隔 */
const COOLDOWN_SECONDS = 15;

/** 每小时最多发几次（换 audience 能绕开单键冷却，用总量兜住） */
const HOURLY_LIMIT = 10;

/** settings 里的冷却标记键前缀 */
const MARKER_PREFIX = 'push_test_';

/** 每小时计数键前缀（键里带 UTC 小时，过期不再用，不需要清理） */
const HOURLY_PREFIX = 'push_test_hour_';

/** 读标记、判断是否还在冷却里（只在占位失败后算剩余秒数用） */
async function readCooldown(db: D1Database, key: string): Promise<number> {
  try {
    const row = await db
      .prepare('SELECT updated_at FROM settings WHERE key = ?')
      .bind(key)
      .first<{ updated_at: string }>();
    if (!row?.updated_at) return 0;
    const elapsed = Date.now() - Date.parse(row.updated_at);
    if (!Number.isFinite(elapsed) || elapsed < 0) return 0;
    const left = COOLDOWN_SECONDS * 1000 - elapsed;
    return left > 0 ? Math.ceil(left / 1000) : 0;
  } catch (error) {
    console.error('read push test marker failed', error);
    return 0;
  }
}

/**
 * 原子占位：冷却已过才写入新时间戳，返回是否抢到。
 * 旧写法「读冷却 → 发推送 → 写冷却」在并发时全部读到「没冷却」，一起发出去；
 * 条件 upsert 里 `WHERE settings.updated_at <= cutoff` 不满足就不更新，`meta.changes === 0` 即没抢到。
 */
async function claimCooldown(
  db: D1Database,
  key: string,
  now: Date
): Promise<{ claimed: boolean; remainingSeconds: number }> {
  const nowIso = now.toISOString();
  const cutoff = new Date(now.getTime() - COOLDOWN_SECONDS * 1000).toISOString();
  try {
    const result = await db
      .prepare(
        `INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?)
          ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
          WHERE settings.updated_at <= ?`
      )
      .bind(key, nowIso, nowIso, cutoff)
      .run();
    if ((result.meta?.changes ?? 0) > 0) return { claimed: true, remainingSeconds: 0 };
  } catch (error) {
    // 表结构出问题不该把「测试通知」整个掐掉
    console.error('claim push test marker failed', error);
    return { claimed: true, remainingSeconds: 0 };
  }
  const left = await readCooldown(db, key);
  return { claimed: false, remainingSeconds: left > 0 ? left : COOLDOWN_SECONDS };
}

/** 每小时配额：原子自增并返回是否仍在额度内（写失败放行，不挡功能） */
async function bumpHourlyCount(db: D1Database, now: Date): Promise<boolean> {
  const hourKey = `${HOURLY_PREFIX}${now.toISOString().slice(0, 13)}`;
  try {
    const result = await db
      .prepare(
        `INSERT INTO settings (key, value, updated_at) VALUES (?, '1', ?)
          ON CONFLICT(key) DO UPDATE SET
            value = CAST(CAST(settings.value AS INTEGER) + 1 AS TEXT),
            updated_at = excluded.updated_at
          RETURNING value`
      )
      .bind(hourKey, now.toISOString())
      .first<{ value: string }>();
    const count = Number.parseInt(result?.value ?? '1', 10);
    return !Number.isFinite(count) || count <= HOURLY_LIMIT;
  } catch (error) {
    console.error('bump push test hourly failed', error);
    return true;
  }
}

/**
 * 把 Worker 的 detail 变成按钮上能看的一句话。
 * Web Push 的 detail 本来就是人话（「已送达 1/1 台设备…」），照用；
 * webhook / bark / ntfy 这几个单目标通道的 detail 是上游响应原文（往往是一段 JSON），
 * 直接显示在设置页里没有意义，所以换成「已发送（通道 webhook）」。
 */
function friendlyDetail(sent: boolean, channel: string | null, raw: string): string {
  if (!sent) return raw || '没有发出任何通知，检查一下通道配置';
  if (channel === 'webpush') return raw || '已发送';
  const trimmed = raw.trim();
  return trimmed && !trimmed.startsWith('{') ? trimmed : `已发送（通道 ${channel ?? '未知'}）`;
}

/** 发一条测试通知（转发给提醒 Worker 的 /trigger?test=1） */
export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  let body: Record<string, unknown> = {};
  try {
    const parsed = await request.json<unknown>();
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
      body = parsed as Record<string, unknown>;
    }
  } catch {
    // 没请求体也行：不传 audience 就是「给所有订阅设备发」
  }

  const rawAudience = body.audience;
  if (rawAudience !== undefined && (typeof rawAudience !== 'string' || !AUDIENCES.includes(rawAudience))) {
    return Response.json({ error: 'audience 非法（应为 parent 或 child）' }, { status: 400 });
  }
  const audience = typeof rawAudience === 'string' ? rawAudience : undefined;

  const reminderUrl = env.REMINDER_URL?.trim().replace(/\/+$/, '') ?? '';
  const token = env.REMIND_TOKEN?.trim() ?? '';
  if (!reminderUrl || !token) {
    return Response.json(
      { error: '服务端还没配提醒 Worker 地址或令牌（REMINDER_URL / REMIND_TOKEN）' },
      { status: 503 }
    );
  }

  const now = new Date();
  const markerKey = `${MARKER_PREFIX}${audience ?? 'all'}`;
  const claim = await claimCooldown(env.DB, markerKey, now);
  if (!claim.claimed) {
    return Response.json(
      { ok: false, cooldown: true, remainingSeconds: claim.remainingSeconds, error: `刚发过，${claim.remainingSeconds} 秒后再试` },
      { status: 429 }
    );
  }
  if (!(await bumpHourlyCount(env.DB, now))) {
    return Response.json(
      { ok: false, error: `每小时最多发 ${HOURLY_LIMIT} 次测试通知，休息一下` },
      { status: 429 }
    );
  }

  const query = new URLSearchParams({ test: '1', force: '1', dry: '0' });
  if (audience) query.set('audience', audience);

  let response: Response;
  try {
    response = await fetch(`${reminderUrl}/trigger?${query.toString()}`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
      // 推送服务商偶尔拖着不回，别让设置页的按钮一直转圈
      signal: AbortSignal.timeout(15_000),
    });
  } catch (error) {
    console.error('call reminder worker failed', error);
    return Response.json({ error: '提醒服务没回应，稍后再试' }, { status: 502 });
  }

  const text = await response.text();
  if (!response.ok) {
    return Response.json({ error: `提醒服务返回 ${response.status}`, detail: text.slice(0, 300) }, { status: 502 });
  }

  let payload: Record<string, unknown> = {};
  try {
    const parsed = JSON.parse(text) as unknown;
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) payload = parsed as Record<string, unknown>;
  } catch {
    // Worker 正常都回 JSON；回不了就按「发出去了但不知道几台」处理
  }

  const sent = payload.sent === true;
  const channel = typeof payload.sendChannel === 'string' ? payload.sendChannel : null;
  const rawDetail = typeof payload.sendDetail === 'string' ? payload.sendDetail : '';

  return Response.json({
    ok: true,
    sent,
    channel,
    detail: friendlyDetail(sent, channel, rawDetail),
    audience: audience ?? 'all',
  });
};
