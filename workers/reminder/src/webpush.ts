/**
 * Web Push 通道（浏览器 / PWA，含 iPhone「添加到主屏幕」后的 Safari）。
 *
 * 为什么它比 ntfy 更适合这个家：孩子用安卓 Chrome 打开网站、妈妈用 iPhone 把网站
 * 添加到主屏幕 —— 两边都不用装任何 App，点一下「开启提醒」就订阅上了。
 * 代价是这套协议要自己算加密（RFC 8291 aes128gcm + VAPID JWT），所以借
 * `@block65/webcrypto-web-push`（纯 WebCrypto、零 node 依赖，Workers 里能跑）。
 *
 * 密钥分工：
 *  - `VAPID_PUBLIC_KEY`  公钥，给浏览器订阅时用，**同时**要配在 Pages 项目里（`GET /api/push/key` 要返回它）
 *  - `VAPID_PRIVATE_KEY` 私钥，只在这个 Worker（secret）
 *  - `VAPID_SUBJECT`     `mailto:` 或 https 地址，推送服务商出问题时用来联系你
 *
 * 订阅存在 D1 的 `push_subscriptions`（由 Pages 的 `POST /api/push/subscribe` 写入），
 * 所以这个 Worker 和 Pages 必须绑**同一个** database_id —— 见 wrangler.jsonc。
 *
 * 推送服务商的响应里 404 / 410 表示「这个订阅已经废了」（用户卸载了 PWA、清了站点数据），
 * 遇到就顺手删掉，免得每次提醒都白跑一趟。
 */
import { buildPushPayload, type PushSubscription } from '@block65/webcrypto-web-push';

import type { PushMessage, PushResult } from './channels';
import type { ReminderEnv } from './env';

/** 通知存活 1 小时（设备离线时推送服务商最多替我们存这么久） */
const TTL_SECONDS = 3600;

interface SubscriptionRow {
  endpoint: string;
  p256dh: string;
  auth: string;
}

export async function sendWebPush(env: ReminderEnv, msg: PushMessage): Promise<PushResult> {
  const publicKey = env.VAPID_PUBLIC_KEY?.trim();
  const privateKey = env.VAPID_PRIVATE_KEY?.trim();
  if (!publicKey || !privateKey) {
    return {
      ok: false,
      status: 0,
      detail:
        'VAPID 密钥未配置：公钥写在 wrangler.jsonc 的 vars 里，私钥用 npx wrangler secret put VAPID_PRIVATE_KEY',
    };
  }
  const subject = env.VAPID_SUBJECT?.trim() || 'https://sekainook.pages.dev';

  let rows: SubscriptionRow[];
  try {
    rows = await readSubscriptions(env, msg);
  } catch (error) {
    console.error('read push_subscriptions failed', error);
    return { ok: false, status: 0, detail: '推送订阅表尚未就绪，请先执行数据库迁移' };
  }
  if (rows.length === 0) {
    return { ok: false, status: 0, detail: '还没有设备订阅推送：在设置页打开「手机提醒」' };
  }

  // Service Worker 里拿到的是这段 JSON 文本
  const data = JSON.stringify({
    title: msg.title,
    message: msg.message,
    click: msg.click ?? env.APP_URL ?? '',
  });

  let sent = 0;
  const expired: string[] = [];
  const failed: string[] = [];

  for (const row of rows) {
    const subscription: PushSubscription = {
      endpoint: row.endpoint,
      expirationTime: null,
      keys: { p256dh: row.p256dh, auth: row.auth },
    };

    try {
      const built = await buildPushPayload(
        { data, options: { ttl: TTL_SECONDS, urgency: 'high', topic: 'sekainook-reminder' } },
        subscription,
        { subject, publicKey, privateKey }
      );
      const res = await fetch(row.endpoint, {
        method: built.method,
        headers: built.headers,
        body: built.body,
        // 推送服务商偶尔会拖着不回（本地走代理联调时尤其明显）；超时就当这一台失败，
        // 不能让它把整次 cron 卡住 —— 提醒该发还得发。
        signal: AbortSignal.timeout(15000),
      });

      if (res.ok) {
        sent += 1;
      } else if (res.status === 404 || res.status === 410) {
        expired.push(row.endpoint);
      } else {
        const text = await res.text().catch(() => '');
        failed.push(`${res.status}${text ? ` ${text.slice(0, 120)}` : ''}`);
      }
    } catch (error) {
      failed.push(error instanceof Error ? error.message : String(error));
    }
  }

  if (expired.length > 0) await deleteSubscriptions(env, expired);

  const parts = [`已送达 ${sent}/${rows.length} 台设备`];
  if (expired.length > 0) parts.push(`清理失效订阅 ${expired.length} 条`);
  if (failed.length > 0) parts.push(`失败 ${failed.length} 条：${failed[0]}`);

  return { ok: sent > 0, status: sent > 0 ? 200 : 0, detail: parts.join('，') };
}

/**
 * 读订阅，按需过滤：
 *  - `msg.endpoint` 指定了某一台 → 只发那一台（自检定点验证用）；
 *  - 否则看 `msg.audience`（覆盖 `PUSH_AUDIENCE`）→ 只发给 parent 或 child 那一侧；
 *  - 都没有 → 全部订阅。
 */
async function readSubscriptions(env: ReminderEnv, msg: PushMessage): Promise<SubscriptionRow[]> {
  const endpoint = msg.endpoint?.trim();
  if (endpoint) {
    const row = await env.DB.prepare(
      'SELECT endpoint, p256dh, auth FROM push_subscriptions WHERE endpoint = ?'
    )
      .bind(endpoint)
      .all<SubscriptionRow>();
    return row.results ?? [];
  }

  const audience = (msg.audience ?? env.PUSH_AUDIENCE)?.trim().toLowerCase();
  const filtered = audience === 'parent' || audience === 'child';

  const sql = `SELECT endpoint, p256dh, auth FROM push_subscriptions${filtered ? ' WHERE audience = ?' : ''}`;
  const statement = env.DB.prepare(sql);
  const result = filtered
    ? await statement.bind(audience).all<SubscriptionRow>()
    : await statement.all<SubscriptionRow>();

  return result.results ?? [];
}

/** 清掉推送服务商说已经失效的订阅（失败不影响本次提醒） */
async function deleteSubscriptions(env: ReminderEnv, endpoints: string[]): Promise<void> {
  try {
    await env.DB.batch(
      endpoints.map((endpoint) =>
        env.DB.prepare('DELETE FROM push_subscriptions WHERE endpoint = ?').bind(endpoint)
      )
    );
  } catch (error) {
    console.warn('清理失效订阅失败（不影响本次提醒）', error);
  }
}
