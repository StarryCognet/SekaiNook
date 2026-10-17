/**
 * 自检检查项：通知、设置、图片、推送、管理员、维护。
 *
 * 写库/发通知类检查一律 `mutates: true` + 默认预演，跑完自己清理；
 * 推送检查走服务端代理（Pages 拿 REMIND_TOKEN 调 Worker），令牌不下发到浏览器。
 */

import { clearAdminLock, readAdminLock } from '../settings';
import {
  clientData,
  dayKeyOf,
  fail,
  head,
  ok,
  previewed,
  readJson,
  selftestId,
  skip,
  warn,
} from './helpers';
import type { SelftestCtx, SelftestItem, SelftestOutcome } from './types';

/* ---------------------------------- 通知 ---------------------------------- */

interface NotifyRow {
  id?: string;
  audience?: string;
  type?: string;
  title?: string;
  status?: string;
  created_at?: string;
}

async function checkNotifyBox(ctx: SelftestCtx, audience: 'parent' | 'child'): Promise<SelftestOutcome> {
  const res = await ctx.api(`/api/notifications?audience=${audience}&limit=200`);
  if (!res.ok) return fail(`GET /api/notifications?audience=${audience} 返回 ${res.status}`);
  const data = await readJson<{ items?: NotifyRow[]; unreadCount?: number; ready?: boolean }>(res);
  if (!Array.isArray(data?.items)) return fail('通知接口没返回 items 数组');
  if (typeof data?.unreadCount !== 'number') return fail('通知接口没返回 unreadCount');
  const leaked = data.items.filter((row) => row.audience && row.audience !== audience);
  if (leaked.length > 0) {
    return fail(`${audience} 信箱里混进了 ${leaked.length} 条别家通知`, '身份隔离必须靠 audience 过滤', head(leaked));
  }
  if (data.ready === false) return warn(`${audience} 信箱 ready=false（通知表可能还没建）`, data);
  return ok(`${audience} 信箱 ${data.items.length} 条、未读 ${data.unreadCount}`, { unreadCount: data.unreadCount });
}

async function checkNotifyInvalid(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const res = await ctx.api('/api/notifications');
  if (res.status !== 400) return fail(`不带 audience 返回 ${res.status}，期望 400`);
  return ok('缺 audience 参数正确返回 400');
}

async function checkNotifyUnread(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const data = await readJson<{ items?: NotifyRow[]; unreadCount?: number }>(
    await ctx.api('/api/notifications?audience=parent&limit=200')
  );
  if (!Array.isArray(data?.items) || typeof data.unreadCount !== 'number') return fail('通知接口结构不对');
  const counted = data.items.filter((row) => row.status === 'unread').length;
  if (data.unreadCount > data.items.length) {
    return warn(`未读数 ${data.unreadCount} 超过本次返回的条数 ${data.items.length}（超过 200 条上限，属正常）`);
  }
  if (counted !== data.unreadCount) {
    return fail(`未读数对不上：接口 ${data.unreadCount}，列表里 ${counted}`, '未读判定应为 status = unread');
  }
  return ok(`未读数一致：${counted}`);
}

async function checkNotifyReadAll(ctx: SelftestCtx): Promise<SelftestOutcome> {
  if (ctx.params.dryRun) return previewed('会把家长信箱全部标记为已读（不可还原，默认不跑）');
  const res = await ctx.api('/api/notifications/read-all', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ audience: 'parent' }),
  });
  const body = await readJson<{ updated?: number }>(res);
  if (!res.ok) return fail(`全部已读返回 ${res.status}`);
  return ok(`家长信箱已全部标记已读（${body?.updated ?? '?'} 条）`);
}

/* ---------------------------------- 设置 ---------------------------------- */

async function checkSettingsGet(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const res = await ctx.api('/api/settings');
  if (!res.ok) return fail(`GET /api/settings 返回 ${res.status}`);
  const data = await readJson<{ names?: Record<string, unknown>; background?: string; ready?: boolean }>(res);
  if (!data?.names) return fail('设置接口没返回 names', undefined, data);
  if (typeof data.names.momCall !== 'string' || typeof data.names.kidCall !== 'string') {
    return fail('家庭称呼缺字段', undefined, data.names);
  }
  return ok(
    `称呼：${data.names.momCall}/${data.names.kidCall}；背景图 ${data.background ? '已设' : '未设'}；ready=${data.ready}`
  );
}

async function checkSettingsNamesRoundtrip(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const before = await readJson<{ names?: Record<string, string> }>(await ctx.api('/api/settings'));
  const original = before?.names?.momNickname ?? '';
  if (ctx.params.dryRun) return previewed(`会把妈妈昵称写成「自检」再还原成「${original || '空'}」`);
  const marker = `自检${Date.now().toString(36).slice(-4)}`;
  const write = await ctx.api('/api/settings', {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ momNickname: marker }),
  });
  const after = await readJson<{ names?: Record<string, string> }>(await ctx.api('/api/settings'));
  const restore = await ctx.api('/api/settings', {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ momNickname: original }),
  });
  if (!write.ok || !restore.ok) return fail(`写入 ${write.status} / 还原 ${restore.status}`);
  if (after?.names?.momNickname !== marker) {
    return fail(`写入后读到的是 ${after?.names?.momNickname}，期望 ${marker}`);
  }
  return ok(`称呼写入并还原成功（原值「${original || '空'}」）`);
}

async function checkSettingsBackgroundGuard(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const res = await ctx.api('/api/settings', {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ background: 'https://evil.example.com/tracker.png' }),
  });
  if (res.status < 400) {
    return fail(`外站背景图被放过了（${res.status}）`, '背景图只允许本站 /api/images/ 下的地址');
  }
  return ok(`外站背景图被拒：${res.status}`);
}

/* ---------------------------------- 图片 ---------------------------------- */

async function checkImageAnonRead(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const records = await readJson<Array<{ image_url?: string | null }>>(await ctx.api('/api/ledger'));
  const url = (Array.isArray(records) ? records : []).map((row) => row.image_url).find((item) => !!item);
  if (!url) return skip('没有带照片的流水，无法验证匿名读取');
  const res = await ctx.api(new URL(url).pathname);
  const allow = res.headers.get('Access-Control-Allow-Origin');
  if (!res.ok) return fail(`GET ${new URL(url).pathname} 返回 ${res.status}`);
  if (allow !== '*') return warn(`图片能读到，但没有 ACAO *（拿到 ${allow}）`);
  return ok(`照片匿名可读（${res.status}，ACAO *）`);
}

/** 1×1 的透明 PNG，用来验证上传链路 */
const TINY_PNG_BASE64 =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==';

function tinyPng(): Uint8Array<ArrayBuffer> {
  const binary = atob(TINY_PNG_BASE64);
  const buffer = new ArrayBuffer(binary.length);
  const bytes = new Uint8Array(buffer);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

async function checkImageUpload(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const bucket = ctx.env.STARRYMIKU_BUCKET;
  if (!bucket) return skip('没有绑定 R2（STARRYMIKU_BUCKET），上传类检查跳过');
  if (ctx.params.dryRun) return previewed('会上传一张 1×1 测试图到 R2，验证后删除');
  const res = await ctx.api('/api/upload', {
    method: 'POST',
    headers: { 'Content-Type': 'image/png' },
    body: new Blob([tinyPng()], { type: 'image/png' }),
  });
  const body = await readJson<{ key?: string; url?: string }>(res);
  if (!res.ok || !body?.key) return fail(`上传返回 ${res.status} ${JSON.stringify(body)}`);
  const read = await ctx.api(`/api/images/${body.key}`);
  let deleted = false;
  if (!ctx.params.keep) {
    await bucket.delete(body.key);
    deleted = true;
  }
  if (!read.ok) return fail(`上传成功但读不回来：${read.status}`);
  return ok(`上传 + 读回成功（${body.key}，${deleted ? '测试对象已删除' : '按 keep=1 保留'}）`);
}

async function checkImageOrphansScan(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const res = await ctx.api('/api/maintenance/orphans');
  if (!res.ok) return fail(`GET /api/maintenance/orphans 返回 ${res.status}`);
  const data = await readJson<{ orphans?: number; referenced?: number; keys?: string[] }>(res);
  if (typeof data?.orphans !== 'number' || !Array.isArray(data.keys)) {
    return fail('扫描结果结构不对', undefined, data);
  }
  return ok(`扫描到 ${data.orphans} 张闲置照片（在用 ${data.referenced ?? '?'} 张）`);
}

async function checkImageOrphansGuard(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const res = await ctx.api('/api/maintenance/orphans', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({}),
  });
  if (res.status < 400) {
    return fail(`不带 confirm 的清理被放过了（${res.status}）`, '删除必须要求 confirm: true');
  }
  return ok(`不带 confirm 的清理被拒：${res.status}`);
}

/* ---------------------------------- 推送 ---------------------------------- */

async function checkPushKey(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const res = await ctx.api('/api/push/key');
  if (!res.ok) return fail(`GET /api/push/key 返回 ${res.status}`);
  const data = await readJson<{ publicKey?: string; subject?: string; ready?: boolean }>(res);
  if (!data?.publicKey || data.publicKey.length < 80) return fail('VAPID 公钥缺失或长度不对', undefined, data);
  if (!data.subject) return fail('VAPID subject 缺失');
  return ok(`VAPID 公钥已下发（${data.publicKey.length} 字符，subject ${data.subject}）`);
}

async function checkPushSubscribeRoundtrip(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const endpoint = `https://selftest.invalid/push/${selftestId('sub')}`;
  if (ctx.params.dryRun) return previewed(`会登记一条假订阅 ${endpoint} 再退订`);
  const body = JSON.stringify({
    endpoint,
    keys: { p256dh: 'selftest-p256dh', auth: 'selftest-auth' },
    audience: 'child',
  });
  const created = await ctx.api('/api/push/subscribe', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body,
  });
  const row = await ctx.db
    .prepare('SELECT endpoint, audience FROM push_subscriptions WHERE endpoint = ?')
    .bind(endpoint)
    .first<{ endpoint: string; audience: string }>();
  const removed = await ctx.api('/api/push/subscribe', {
    method: 'DELETE',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ endpoint }),
  });
  const gone = await ctx.db
    .prepare('SELECT endpoint FROM push_subscriptions WHERE endpoint = ?')
    .bind(endpoint)
    .first<{ endpoint: string }>();
  if (!created.ok) return fail(`登记订阅返回 ${created.status}`);
  if (!row) return fail('登记成功但库里没有这条订阅');
  if (!removed.ok) return fail(`退订返回 ${removed.status}`);
  if (gone) return fail('退订后订阅还在库里');
  return ok(`订阅登记 → 落库（audience ${row.audience}）→ 退订 → 已清除`);
}

async function checkPushSubscribeGuard(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const res = await ctx.api('/api/push/subscribe', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ endpoint: 'http://not-https.example/x', keys: { p256dh: 'a', auth: 'b' } }),
  });
  if (res.status !== 400) return fail(`非 https 的 endpoint 返回 ${res.status}，期望 400`);
  return ok('非 https endpoint 被拒：400');
}

async function checkPushList(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const result = await ctx.db
    .prepare('SELECT endpoint, audience, ua, updated_at FROM push_subscriptions ORDER BY updated_at DESC')
    .all<{ endpoint: string; audience: string; ua: string | null; updated_at: string }>();
  const rows = result.results ?? [];
  const byAudience = rows.reduce<Record<string, number>>((acc, row) => {
    acc[row.audience] = (acc[row.audience] ?? 0) + 1;
    return acc;
  }, {});
  const masked = rows.map((row) => ({
    endpoint: `${row.endpoint.slice(0, 32)}…${row.endpoint.slice(-6)}`,
    audience: row.audience,
    ua: row.ua ?? '',
    updatedAt: row.updated_at,
  }));
  if (rows.length === 0) return warn('当前一台设备都没订阅（开启提醒后才会出现）');
  return ok(`已订阅 ${rows.length} 台：${JSON.stringify(byAudience)}`, { subscriptions: masked });
}

async function checkPushMarker(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const dayKey = dayKeyOf(ctx);
  const row = await ctx.db
    .prepare('SELECT key, value, updated_at FROM settings WHERE key = ?')
    .bind(`reminder_sent_${dayKey}`)
    .first<{ key: string; value: string; updated_at: string }>();
  if (!row) return ok(`${dayKey} 还没有发送标记（今天还没推过，或推失败了已释放）`);
  return ok(`${dayKey} 已发过提醒（标记 ${row.key} = ${row.value}）`, row);
}

async function checkWorkerHealth(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const res = await ctx.worker('/health');
  if (!res.ok) return fail(`Worker /health 返回 ${res.status}`, '检查 wrangler.jsonc 的 REMINDER_URL 与 REMIND_TOKEN');
  const data = await readJson<Record<string, unknown>>(res);
  if (!data?.target) return fail('Worker /health 结构不对', undefined, data);
  return ok(`Worker 在线：通道 ${data.channel}，阈值 ${data.target}，截止 ${data.deadline}`, data);
}

async function checkWorkerDryRun(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const query = new URLSearchParams({ dry: '1' });
  if (ctx.params.dayKey) query.set('now', `${ctx.params.dayKey}T13:30:00.000Z`);
  const res = await ctx.worker(`/trigger?${query.toString()}`, { method: 'POST' });
  if (!res.ok) return fail(`Worker /trigger?dry=1 返回 ${res.status}`);
  const data = await readJson<{ dayKey?: string; done?: number; remaining?: number; shouldSend?: boolean; title?: string }>(res);
  if (typeof data?.done !== 'number' || typeof data.remaining !== 'number') {
    return fail('Worker 预演返回结构不对', undefined, data);
  }
  return ok(`预演：${data.dayKey} 已完成 ${data.done}/5，还差 ${data.remaining}，shouldSend=${data.shouldSend}`, data);
}

async function checkPushSend(ctx: SelftestCtx): Promise<SelftestOutcome> {
  if (ctx.params.dryRun) return previewed('会真的发一条通知到已订阅的设备（可自定义文案/通道/目标）');
  // 这一项存在的意义就是「真的发一条」，所以显式 dry=0 压掉 Worker 上的 DRY_RUN（本地联调常驻 1）
  const query = new URLSearchParams({ force: '1', dry: '0' });
  if (ctx.params.channel) query.set('channel', ctx.params.channel);
  if (ctx.params.audience && ctx.params.audience !== 'all') query.set('audience', ctx.params.audience);
  if (ctx.params.endpoint) query.set('endpoint', ctx.params.endpoint);
  if (ctx.params.title) query.set('title', ctx.params.title);
  if (ctx.params.message) query.set('message', ctx.params.message);
  if (ctx.params.priority) query.set('priority', String(ctx.params.priority));
  if (ctx.params.simulateDone !== null) query.set('simulateDone', String(ctx.params.simulateDone));
  const res = await ctx.worker(`/trigger?${query.toString()}`, { method: 'POST' });
  const data = await readJson<Record<string, unknown>>(res);
  if (!res.ok) return fail(`发送返回 ${res.status}`, undefined, data);
  if (data?.skipped === 'already-sent') {
    return warn('今天已经提醒过了（幂等标记还在），这次没有真发', data);
  }
  if (data?.sent === false) {
    const detail = String(data.sendDetail ?? data.reason ?? JSON.stringify(data));
    if (detail.includes('还没有设备订阅')) {
      return warn(`没有可发的设备：${detail}`, data);
    }
    return fail(`没有发出去：${detail}`, undefined, data);
  }
  return ok(`已发送（通道 ${data?.sendChannel ?? data?.channel ?? '?'}，状态 ${data?.sendStatus ?? '?'}）`, data);
}

/* --------------------------------- 管理员 --------------------------------- */

async function checkAdminWrongPassword(ctx: SelftestCtx): Promise<SelftestOutcome> {
  if (ctx.params.dryRun) return previewed('会提交一次错误密码（验证 401 + 剩余次数），随后清掉失败计数');
  const res = await ctx.api('/api/admin', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: 'verify', password: 'selftest-wrong-password' }),
  });
  const data = await readJson<{ error?: string; attemptsLeft?: number; lockRemainingMs?: number }>(res);
  await clearAdminLock(ctx.db); // 自检不能把家长锁在门外
  if (res.status !== 401 && res.status !== 429) {
    return fail(`错误密码返回 ${res.status}，期望 401（或锁定期 429）`, undefined, data);
  }
  return ok(`错误密码被拒：${res.status} ${data?.error ?? ''}（失败计数已清零）`);
}

async function checkAdminLockState(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const lock = await readAdminLock(ctx.db);
  if (typeof lock.failedAttempts !== 'number' || typeof lock.lockRemainingMs !== 'number') {
    return fail('节流状态读取失败', undefined, lock);
  }
  if (lock.lockRemainingMs > 0) {
    return warn(`管理员正处在锁定期，还剩 ${Math.ceil(lock.lockRemainingMs / 1000)} 秒`);
  }
  return ok(`未锁定，已失败 ${lock.failedAttempts} 次`);
}

async function checkAdminAdjustNoop(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const password = ctx.password;
  if (!password) return skip('这一轮没带管理员密码（内部检查项）');
  const before = await readJson<{ family?: number }>(await ctx.api('/api/ledger/summary'));
  const family = before?.family;
  if (typeof family !== 'number') return fail('读不到当前余额');
  const res = await ctx.api('/api/admin', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: 'adjust', password, family }),
  });
  const data = await readJson<{ family?: number; changed?: string[] }>(res);
  if (!res.ok) return fail(`调整接口返回 ${res.status}`, undefined, data);
  if (data?.family !== family) return fail(`把余额改成当前值却变了：${family} → ${data?.family}`);
  return ok(`按当前值调整不会写流水（差额 0），余额仍为 ${family}`);
}

async function checkAdminAdjustments(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const password = ctx.password;
  if (!password) return skip('这一轮没带管理员密码（内部检查项）');
  const res = await ctx.api('/api/admin', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: 'adjustments', password }),
  });
  const data = await readJson<{ adjustments?: unknown[] }>(res);
  if (!res.ok) return fail(`最近调整列表返回 ${res.status}`, undefined, data);
  if (!Array.isArray(data?.adjustments)) return fail('最近调整不是数组');
  return ok(`最近调整 ${data.adjustments.length} 条`);
}

async function checkAdminResetPreview(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const summary = await readJson<{ family?: number; sun?: number }>(await ctx.api('/api/ledger/summary'));
  if (typeof summary?.family !== 'number' || typeof summary.sun !== 'number') return fail('读不到余额');
  return ok(
    `一键清零会写两条调整流水：家庭 ${summary.family} → 0（${-summary.family}）、阳光 ${summary.sun} → 0（${-summary.sun}）`,
    { delta: { family: -summary.family, sun: -summary.sun } }
  );
}

/* --------------------------------- 维护 ----------------------------------- */

async function checkSettingsKeys(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const result = await ctx.db
    .prepare('SELECT key, length(value) AS len, updated_at FROM settings ORDER BY key')
    .all<{ key: string; len: number; updated_at: string }>();
  const rows = result.results ?? [];
  const keys = rows.map((row) => row.key);
  if (keys.length === 0) return warn('settings 表是空的（迁移后还没写过任何设置）');
  return ok(`settings 里 ${keys.length} 个键`, { keys: rows });
}

async function checkLedgerTimestamps(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const result = await ctx.db
    .prepare('SELECT id, created_at FROM family_ledger ORDER BY created_at DESC LIMIT 500')
    .all<{ id: string; created_at: string }>();
  const rows = result.results ?? [];
  const bad = rows.filter((row) => Number.isNaN(Date.parse(row.created_at)));
  if (bad.length > 0) return fail(`${bad.length} 条流水的 created_at 不是合法时间`, undefined, head(bad));
  const future = rows.filter((row) => Date.parse(row.created_at) > Date.now() + 86_400_000);
  if (future.length > 0) return warn(`${future.length} 条流水的时间在一天以后（时区写错？）`, head(future));
  return ok(`${rows.length} 条流水时间戳都合法，最新 ${rows[0]?.created_at ?? '—'}`);
}

async function checkClientNotifyText(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const reported = clientData<{ title?: string; message?: string }>(ctx.params, 'client.notify.today');
  if (!reported?.message) return skip('客户端没上报本地提醒文案（本地检查项 client.notify.today 未跑）');
  const expected = await ctx.worker('/trigger?dry=1', { method: 'POST' }).then((res) =>
    readJson<{ title?: string; message?: string }>(res)
  );
  if (!expected?.message) return warn('服务端预演没返回文案，无法比对');
  if (reported.message !== expected.message) {
    return fail(
      '客户端本地提醒文案与服务端不一致',
      '两端都从「已完成 X/5」推导，口径必须一致',
      { client: reported, server: expected }
    );
  }
  return ok('客户端本地提醒文案与服务端一致');
}

export const REST_ITEMS: SelftestItem[] = [
  { id: 'notify.parent', name: '家长信箱', desc: '结构、未读数、身份隔离', group: 'notify', side: 'server', estMs: 100, run: (ctx) => checkNotifyBox(ctx, 'parent') },
  { id: 'notify.child', name: '孩子信箱', desc: '结构、未读数、身份隔离', group: 'notify', side: 'server', estMs: 100, run: (ctx) => checkNotifyBox(ctx, 'child') },
  { id: 'notify.invalid', name: '缺 audience 被拒', desc: '参数校验', group: 'notify', side: 'server', estMs: 60, run: checkNotifyInvalid },
  { id: 'notify.unread', name: '未读数一致', desc: 'unreadCount vs 列表里的 unread', group: 'notify', side: 'server', estMs: 100, run: checkNotifyUnread },
  { id: 'notify.read_all', name: '全部已读', desc: '会把家长信箱清空未读（不可还原）', group: 'notify', side: 'server', mutates: true, danger: 'write', uses: ['dryRun'], estMs: 120, run: checkNotifyReadAll },
  { id: 'notify.client.text', name: '提醒文案跨端对账', desc: '客户端本地提醒文案 vs 服务端预演', group: 'notify', side: 'server', estMs: 120, run: checkClientNotifyText },

  { id: 'settings.get', name: '设置读取', desc: '称呼、背景图、ready', group: 'settings', side: 'server', estMs: 80, run: checkSettingsGet },
  { id: 'settings.names.roundtrip', name: '称呼读写往返', desc: '写入后读回一致并还原', group: 'settings', side: 'server', mutates: true, danger: 'write', uses: ['dryRun'], estMs: 200, run: checkSettingsNamesRoundtrip },
  { id: 'settings.background.guard', name: '外站背景图被拒', desc: '只允许本站图片', group: 'settings', side: 'server', estMs: 80, run: checkSettingsBackgroundGuard },

  { id: 'images.anon_read', name: '照片匿名可读', desc: '带照片的流水能否直接读到 + ACAO', group: 'images', side: 'server', estMs: 120, run: checkImageAnonRead },
  { id: 'images.upload', name: '上传链路', desc: '上传 1×1 测试图 → 读回 → 删除', group: 'images', side: 'server', mutates: true, danger: 'write', uses: ['dryRun', 'keep'], estMs: 300, run: checkImageUpload },
  { id: 'images.orphans.scan', name: '闲置照片扫描', desc: '扫描结果结构', group: 'images', side: 'server', estMs: 300, run: checkImageOrphansScan },
  { id: 'images.orphans.guard', name: '清理必须确认', desc: '不带 confirm 的清理要被拒', group: 'images', side: 'server', estMs: 80, run: checkImageOrphansGuard },

  { id: 'push.key', name: 'VAPID 公钥', desc: 'GET /api/push/key', group: 'push', side: 'server', estMs: 80, run: checkPushKey },
  { id: 'push.subscribe.roundtrip', name: '订阅登记/退订', desc: '假订阅落库后清除', group: 'push', side: 'server', mutates: true, danger: 'write', uses: ['dryRun'], estMs: 250, run: checkPushSubscribeRoundtrip },
  { id: 'push.subscribe.guard', name: '订阅参数校验', desc: '非 https endpoint 要被拒', group: 'push', side: 'server', estMs: 80, run: checkPushSubscribeGuard },
  { id: 'push.list', name: '订阅设备清单', desc: '库里有多少台设备订阅', group: 'push', side: 'server', estMs: 60, run: checkPushList },
  { id: 'push.marker', name: '当天发送标记', desc: '今天推没推过', group: 'push', side: 'server', estMs: 60, run: checkPushMarker },
  { id: 'push.worker.health', name: 'Worker 在线', desc: '提醒 Worker 的 /health', group: 'push', side: 'server', estMs: 300, run: checkWorkerHealth },
  { id: 'push.worker.dry', name: 'Worker 预演', desc: '/trigger?dry=1 的完成数与文案', group: 'push', side: 'server', uses: ['dayKey'], estMs: 300, run: checkWorkerDryRun },
  { id: 'push.send', name: '真发一条通知', desc: '可自定义文案/通道/目标设备', group: 'push', side: 'server', mutates: true, danger: 'write', uses: ['dryRun', 'channel', 'audience', 'endpoint', 'title', 'message', 'priority', 'simulateDone'], estMs: 1500, run: checkPushSend },

  { id: 'admin.wrong_password', name: '错误密码被拒', desc: '401 + 剩余次数，跑完清失败计数', group: 'admin', side: 'server', mutates: true, danger: 'write', uses: ['dryRun'], estMs: 150, run: checkAdminWrongPassword },
  { id: 'admin.lock_state', name: '节流状态', desc: '失败次数与锁定期', group: 'admin', side: 'server', estMs: 60, run: checkAdminLockState },
  { id: 'admin.adjust.noop', name: '按当前值调整', desc: '差额为 0 时不写流水', group: 'admin', side: 'server', estMs: 150, run: checkAdminAdjustNoop },
  { id: 'admin.adjustments', name: '最近调整列表', desc: '管理员调整的留痕', group: 'admin', side: 'server', estMs: 120, run: checkAdminAdjustments },
  { id: 'admin.reset.preview', name: '一键清零预演', desc: '会写哪两条调整流水', group: 'admin', side: 'server', estMs: 120, run: checkAdminResetPreview },

  { id: 'maintenance.settings_keys', name: 'settings 键体检', desc: '键清单与长度', group: 'maintenance', side: 'server', estMs: 60, run: checkSettingsKeys },
  { id: 'maintenance.timestamps', name: '流水时间戳', desc: '合法性与未来时间', group: 'maintenance', side: 'server', estMs: 80, run: checkLedgerTimestamps },
];
