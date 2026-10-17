/**
 * 推送通道。`sendPush` 是唯一出口，reminder.ts 不关心用的是哪条通道 ——
 * 以后要加 FCM / Web Push，在这里加一个 `sendFcm` 并按 env 选择即可。
 *
 * 现在有四条，按「手机上是哪个系统 / 愿不愿意装 App」选：
 *  - `webpush` **默认推荐**。浏览器/PWA 原生推送：孩子安卓 Chrome 直接开网站、
 *              妈妈 iPhone 把网站添加到主屏幕，点一下「开启提醒」就订阅上了，**不用装 App**。
 *              订阅存在 D1 的 `push_subscriptions`，实现在 `webpush.ts`
 *  - `ntfy`    装 ntfy App（Android / iOS 都有）订阅一个主题；零账号、零证书
 *  - `bark`    iOS 专用。装 Bark App 拿到一个 key，`POST api.day.app/push` 就推过去了；
 *              不需要账号、不需要开发者证书，是 iOS 上最省事的一条
 *  - `webhook` 通用 JSON POST：Server酱 / PushDeer / 自建 ntfy / 自己的机器人，都能接
 *
 * 选哪条由 `PUSH_CHANNEL` 决定；没设就按「配了哪个用哪个」猜
 * （BARK_KEY → webhook → VAPID 密钥齐了 → webpush → 兜底 ntfy）。
 *
 * ⚠️ 一个实测坑（2026-10 记）：**ntfy.sh 免费版对 Cloudflare Worker 不可靠** ——
 * 它的限额按出口 IP 算，而 Worker 的出口 IP 是所有 Cloudflare 客户共用的，
 * 别人的流量会把当天额度用光，于是我们发出去得到
 * `42908 limit reached: daily message quota reached`。
 * 同一时刻从家用宽带直连 ntfy.sh 却是 200。所以生产上要么用 `bark` / `webhook`，
 * 要么自建 ntfy（`NTFY_SERVER` 指自己的域名），要么买 ntfy 付费版。
 */
import { sendWebPush } from './webpush';
import type { ReminderEnv } from './env';

export interface PushMessage {
  title: string;
  message: string;
  /** 优先级 1~5，4 = high（会浮到锁屏顶部） */
  priority?: number;
  /** 标签（emoji shortcode 或内置名），显示在通知标题前 */
  tags?: string[];
  /** 点通知打开哪个页面 */
  click?: string;
  /**
   * 只发给这一侧的设备（覆盖 env.PUSH_AUDIENCE）。目前只有 webpush 通道支持按 audience 过滤
   * （订阅表里有 audience 字段），自检控制台用它做「只测妈妈那台」。
   */
  audience?: 'parent' | 'child';
  /** 只发给这一台设备（push_subscriptions.endpoint），自检里用来定点验证某一台 */
  endpoint?: string;
}

export interface PushResult {
  ok: boolean;
  status: number;
  detail?: string;
  /** 实际用了哪条通道（写进日志，排查时一眼看出） */
  channel?: string;
}

export const PUSH_CHANNELS = ['ntfy', 'bark', 'webhook', 'webpush'] as const;

export type PushChannel = (typeof PUSH_CHANNELS)[number];

export function pickChannel(env: ReminderEnv): PushChannel {
  const explicit = env.PUSH_CHANNEL?.trim().toLowerCase();
  if (explicit && (PUSH_CHANNELS as readonly string[]).includes(explicit)) {
    return explicit as PushChannel;
  }
  if (env.BARK_KEY?.trim()) return 'bark';
  if (env.PUSH_WEBHOOK_URL?.trim()) return 'webhook';
  if (env.VAPID_PUBLIC_KEY?.trim() && env.VAPID_PRIVATE_KEY?.trim()) return 'webpush';
  return 'ntfy';
}

export async function sendPush(
  env: ReminderEnv,
  msg: PushMessage,
  override?: PushChannel
): Promise<PushResult> {
  const channel = override ?? pickChannel(env);
  const result =
    channel === 'bark'
      ? await sendBark(env, msg)
      : channel === 'webhook'
        ? await sendWebhook(env, msg)
        : channel === 'webpush'
          ? await sendWebPush(env, msg)
          : await sendNtfy(env, msg);
  return { ...result, channel };
}

/** ntfy：POST 到根路径、topic 写在 body 里（不用 `POST /<topic>`，少一处让主题名进日志的地方） */
async function sendNtfy(env: ReminderEnv, msg: PushMessage): Promise<PushResult> {
  const topic = env.NTFY_TOPIC?.trim();
  if (!topic) {
    return { ok: false, status: 0, detail: 'NTFY_TOPIC 未配置：npx wrangler secret put NTFY_TOPIC' };
  }

  const server = (env.NTFY_SERVER?.trim() || 'https://ntfy.sh').replace(/\/+$/, '');
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (env.NTFY_TOKEN) headers.Authorization = `Bearer ${env.NTFY_TOKEN}`;

  return await request(`${server}/`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      topic,
      title: msg.title,
      message: msg.message,
      priority: msg.priority ?? 4,
      tags: msg.tags ?? ['bell'],
      ...(msg.click ? { click: msg.click } : {}),
    }),
  });
}

/** Bark：iOS 上最省事的一条，`POST /push` + device_key */
async function sendBark(env: ReminderEnv, msg: PushMessage): Promise<PushResult> {
  const key = env.BARK_KEY?.trim();
  if (!key) {
    return { ok: false, status: 0, detail: 'BARK_KEY 未配置：npx wrangler secret put BARK_KEY' };
  }

  const server = (env.BARK_SERVER?.trim() || 'https://api.day.app').replace(/\/+$/, '');
  return await request(`${server}/push`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      device_key: key,
      title: msg.title,
      body: msg.message,
      group: 'SekaiNook',
      level: 'active',
      ...(msg.click ? { url: msg.click } : {}),
    }),
  });
}

/** 通用 webhook：body 是 { title, message, priority, tags, click }，额外请求头走 PUSH_WEBHOOK_HEADERS */
async function sendWebhook(env: ReminderEnv, msg: PushMessage): Promise<PushResult> {
  const url = env.PUSH_WEBHOOK_URL?.trim();
  if (!url) {
    return { ok: false, status: 0, detail: 'PUSH_WEBHOOK_URL 未配置' };
  }

  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (env.PUSH_WEBHOOK_HEADERS?.trim()) {
    try {
      const extra = JSON.parse(env.PUSH_WEBHOOK_HEADERS) as Record<string, string>;
      for (const [k, v] of Object.entries(extra)) headers[k] = String(v);
    } catch {
      console.warn('PUSH_WEBHOOK_HEADERS 不是合法 JSON，已忽略');
    }
  }

  return await request(url, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      title: msg.title,
      message: msg.message,
      priority: msg.priority ?? 4,
      tags: msg.tags ?? ['bell'],
      click: msg.click ?? null,
    }),
  });
}

async function request(url: string, init: RequestInit): Promise<PushResult> {
  try {
    const res = await fetch(url, init);
    const text = await res.text().catch(() => '');
    return { ok: res.ok, status: res.status, detail: text.slice(0, 300) || undefined };
  } catch (error) {
    return {
      ok: false,
      status: 0,
      detail: error instanceof Error ? error.message : String(error),
    };
  }
}
