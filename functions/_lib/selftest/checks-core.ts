/**
 * 自检检查项：基础环境 + 账本。
 *
 * 每条检查项都是「打真实接口 → 断言 → 一句话结论」，写库类的一律自己清理。
 */

import {
  GARDEN_ID_PREFIXES,
  LEDGER_TASK_RULES,
  countDayCompletions,
  isGardenTaskId,
} from '../rules';
import {
  boundsOf,
  clientData,
  dayKeyOf,
  deleteLedgerRecord,
  fail,
  fetchAllRecords,
  head,
  ok,
  previewed,
  readJson,
  readText,
  selftestId,
  skip,
  warn,
  type LedgerRowLike,
} from './helpers';
import type { SelftestCtx, SelftestItem, SelftestOutcome } from './types';

/* --------------------------------- 基础环境 -------------------------------- */

const EXPECTED_TABLES = [
  'family_ledger',
  'weekly_plans',
  'notifications',
  'settings',
  'push_subscriptions',
  'changelog',
  'd1_migrations',
];

async function checkBindings(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const row = await ctx.db.prepare('SELECT 1 AS one').first<{ one: number }>();
  if (row?.one !== 1) return fail('DB 绑定查不到东西', '检查 wrangler.jsonc 的 d1_databases 绑定名是否为 DB');
  const r2 = ctx.env.STARRYMIKU_BUCKET ? '已绑定' : '未绑定（上传/清理类检查会跳过）';
  const worker = ctx.env.REMINDER_URL ? ctx.env.REMINDER_URL : '未配置 REMINDER_URL（推送类检查会失败）';
  return ok(`DB 可查询；R2 ${r2}；提醒 Worker ${worker}`);
}

async function checkTables(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const result = await ctx.db
    .prepare(`SELECT name FROM sqlite_master WHERE type = 'table'`)
    .all<{ name: string }>();
  const names = new Set((result.results ?? []).map((row) => row.name));
  const missing = EXPECTED_TABLES.filter((table) => !names.has(table));
  if (missing.length > 0) {
    return fail(
      `缺表：${missing.join('、')}`,
      '按顺序跑 npx wrangler d1 migrations apply sekainook --local / --remote'
    );
  }
  return ok(`7 张表齐全（共 ${names.size} 张）`);
}

async function checkMigrations(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const result = await ctx.db
    .prepare(`SELECT name FROM d1_migrations ORDER BY id`)
    .all<{ name: string }>();
  const names = (result.results ?? []).map((row) => row.name);
  if (names.length === 0) return fail('d1_migrations 是空的', '数据库还没跑过任何迁移');
  const latest = names[names.length - 1] ?? '';
  if (!latest.startsWith('0006')) {
    return warn(`最新迁移是 ${latest}，期望 0006_changelog.sql`, { migrations: names });
  }
  return ok(`${names.length} 条迁移，最新 ${latest}`, { migrations: names });
}

/**
 * 版本日志（0006 之后上的云）。
 *
 * 为什么要专门查一条：上云之后「迁移跑了、但忘了同步内容」是个**静默失败** ——
 * 接口会老老实实回 ready:false，两端也照常显示（各自退回 bundle 里那份兜底），
 * 页面上一片祥和，只有日志停在旧版本。这条检查就是把这个坑照出来。
 */
interface ChangelogPayload {
  version?: unknown;
  entries?: unknown;
  ready?: unknown;
}

async function checkChangelog(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const res = await ctx.api('/api/changelog');
  if (!res.ok) return fail(`GET /api/changelog 返回 ${res.status}`);
  const data = await readJson<ChangelogPayload>(res);
  if (!data || !Array.isArray(data.entries)) return fail('返回里没有 entries 数组', undefined, data);

  const rows = data.entries as Array<Record<string, unknown>>;
  if (rows.length === 0 || data.ready !== true) {
    return warn(
      '云端还没有版本日志（两端会退回各自 bundle 里那份）',
      '先跑 npm run db:migrate:remote，再跑 npm run changelog:sync'
    );
  }

  const broken = rows.filter(
    (row) =>
      typeof row.version !== 'string' ||
      typeof row.date !== 'string' ||
      typeof row.title !== 'string' ||
      !Array.isArray(row.changes)
  );
  if (broken.length > 0) {
    return fail(`${broken.length} 条日志字段不全`, 'version/date/title/changes 缺一不可', head(broken));
  }

  const versions = rows.map((row) => String(row.version));
  if (new Set(versions).size !== versions.length) {
    return fail('版本号有重复', 'version 是主键，重复说明同步把表写坏了');
  }
  if (data.version !== versions[0]) {
    return fail(`返回的 version（${String(data.version)}）不是第一条（${versions[0]}）`);
  }

  const empty = rows.filter((row) => (row.changes as unknown[]).length === 0);
  if (empty.length > 0) {
    return warn(`${empty.length} 条日志没有改动条目`, { versions: empty.map((row) => String(row.version)) });
  }

  return ok(`${rows.length} 条版本日志，最新 v${versions[0]}`, { latest: versions[0] });
}

async function checkCors(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const res = await ctx.api('/api/ledger', {
    method: 'OPTIONS',
    headers: { Origin: 'https://selftest.example', 'Access-Control-Request-Method': 'GET' },
  });
  const allow = res.headers.get('Access-Control-Allow-Origin');
  if (res.status !== 204) return fail(`预检返回 ${res.status}，期望 204`, '看 functions/_middleware.ts 的 OPTIONS 分支');
  if (allow !== '*') return fail(`预检没有 Access-Control-Allow-Origin（拿到 ${allow}）`);
  return ok('OPTIONS /api/ledger → 204 + ACAO *');
}

async function checkNotFound(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const res = await ctx.api('/api/__selftest_missing_route__');
  if (res.status !== 404) return fail(`不存在的接口返回 ${res.status}，期望 404`);
  return ok('未知 /api 路径返回 404');
}

async function checkServiceWorker(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const res = await ctx.api('/sw.js');
  if (!res.ok) return fail(`GET /sw.js 返回 ${res.status}`);
  const text = await readText(res);
  const hasPush = /addEventListener\(\s*['"]push['"]/.test(text);
  const hasClick = /addEventListener\(\s*['"]notificationclick['"]/.test(text);
  if (!hasPush) return fail('/sw.js 里没有 push 监听', 'Web Push 靠它收通知，见 public/sw.js');
  if (!hasClick) return warn('/sw.js 有 push 监听，但没有 notificationclick（点通知不会跳转）');
  return ok(`/sw.js 已就绪（push + notificationclick，${text.length} 字节）`);
}

async function checkManifest(ctx: SelftestCtx): Promise<SelftestOutcome> {
  // 清单文件名是 manifest.webmanifest（index.html 里就是这么引的）；
  // 顺手也认一下 manifest.json，方便以后改名时不至于把自检卡死
  let path = '/manifest.webmanifest';
  let res = await ctx.api(path);
  if (!res.ok) {
    path = '/manifest.json';
    res = await ctx.api(path);
  }
  if (!res.ok) return fail(`GET /manifest.webmanifest 返回 ${res.status}`, 'public/manifest.webmanifest 必须存在');
  const data = await readJson<{ name?: string; theme_color?: string }>(res);
  if (!data?.name) return fail(`${path} 里没有 name`);
  return ok(`PWA 清单可读（${path}）：${data.name}（主题色 ${data.theme_color ?? '未设'}）`);
}

/* ---------------------------------- 账本 ---------------------------------- */

interface RawRecord extends LedgerRowLike {
  member?: string | null;
}

async function checkLedgerList(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const res = await ctx.api('/api/ledger');
  if (!res.ok) return fail(`GET /api/ledger 返回 ${res.status}`);
  const data = await readJson<RawRecord[]>(res);
  if (!Array.isArray(data)) return fail('GET /api/ledger 返回的不是数组');
  const broken = data.filter(
    (row) => !row || typeof row.id !== 'string' || typeof row.task_id !== 'string' || typeof row.amount !== 'number'
  );
  if (broken.length > 0) return fail(`${broken.length} 条流水的字段不全`, '需要 id/task_id/task_name/type/amount/created_at');
  const badType = data.filter((row) => row.type !== 'earning' && row.type !== 'spending');
  if (badType.length > 0) return fail(`${badType.length} 条流水的 type 不是 earning/spending`, undefined, head(badType));
  const ids = new Set(data.map((row) => row.id));
  if (ids.size !== data.length) return fail('流水 id 有重复', '主键应当唯一');
  return ok(`${data.length} 条流水，字段与类型都对`, { sample: head(data, 2) });
}

async function checkPendingFilter(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const res = await ctx.api('/api/ledger?status=pending');
  if (!res.ok) return fail(`GET /api/ledger?status=pending 返回 ${res.status}`);
  const data = await readJson<RawRecord[]>(res);
  if (!Array.isArray(data)) return fail('待审批接口返回的不是数组');
  const leaked = data.filter((row) => row.status !== 'pending');
  if (leaked.length > 0) return fail(`待审批列表里混进了 ${leaked.length} 条非 pending`, undefined, head(leaked));
  return ok(`待审批 ${data.length} 条，全是 pending`);
}

async function checkSummaryShape(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const res = await ctx.api('/api/ledger/summary');
  if (!res.ok) return fail(`GET /api/ledger/summary 返回 ${res.status}`);
  const data = await readJson<{ family?: unknown; sun?: unknown }>(res);
  if (typeof data?.family !== 'number' || typeof data?.sun !== 'number') {
    return fail('余额接口没返回两个数字', undefined, data);
  }
  return ok(`family ${data.family} / sun ${data.sun}`, data);
}

/** 核心对账：余额接口的两个数字，必须等于按同口径重算的流水合计 */
async function checkSummaryReconcile(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const [recordsRes, summaryRes] = await Promise.all([
    ctx.api('/api/ledger'),
    ctx.api('/api/ledger/summary'),
  ]);
  const records = await readJson<RawRecord[]>(recordsRes);
  const summary = await readJson<{ family?: number; sun?: number }>(summaryRes);
  if (!Array.isArray(records) || typeof summary?.family !== 'number' || typeof summary.sun !== 'number') {
    return fail('对账所需的数据没取到');
  }
  let family = 0;
  let sun = 0;
  for (const row of records) {
    const credited = !row.status || row.status === 'approved';
    if (!credited) continue;
    if (isGardenTaskId(row.task_id)) sun += row.amount;
    else family += row.amount;
  }
  const data = { summary: { family: summary.family, sun: summary.sun }, recalc: { family, sun } };
  if (family !== summary.family || sun !== summary.sun) {
    return fail(
      `对不上：summary family ${summary.family} / sun ${summary.sun}，重算 family ${family} / sun ${sun}`,
      '先看有没有绕过接口直接改库、或漏了 status 判断与花园前缀',
      data
    );
  }
  return ok(`family ${family} = ${summary.family}，sun ${sun} = ${summary.sun}`, data);
}

async function checkGardenSplit(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const records = await fetchAllRecords(ctx);
  const garden = records.filter((row) => isGardenTaskId(row.task_id));
  const suspicious = garden.filter(
    (row) => !GARDEN_ID_PREFIXES.some((prefix) => row.task_id.startsWith(prefix))
  );
  if (suspicious.length > 0) return fail(`${suspicious.length} 条花园流水的 id 前缀不认识`, undefined, head(suspicious));
  return ok(`${garden.length} 条花园流水 / ${records.length - garden.length} 条家庭流水，前缀都合法`);
}

/** 写一条自检流水；返回 id 与创建响应（失败返回 null） */
async function createTestRecord(
  ctx: SelftestCtx,
  extra: Record<string, unknown> = {}
): Promise<{ id: string; res: Response; body: Record<string, unknown> | null }> {
  const id = selftestId('selftest');
  const res = await ctx.api('/api/ledger', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      id,
      task_id: ctx.params.taskId,
      task_name: '自检',
      type: 'earning',
      amount: ctx.params.amount,
      note: ctx.params.note,
      ...extra,
    }),
  });
  const body = await readJson<Record<string, unknown>>(res);
  return { id, res, body };
}

async function checkWriteIdempotent(ctx: SelftestCtx): Promise<SelftestOutcome> {
  if (ctx.params.dryRun) return previewed('会写一条流水并重复提交同 id，验证 duplicate');
  const first = await createTestRecord(ctx);
  if (!first.res.ok) {
    return fail(`首次写入失败：${first.res.status} ${JSON.stringify(first.body)}`, '确认 taskId 是真实任务且金额与服务端规则一致');
  }
  const second = await createTestRecord(ctx, { id: first.id });
  const duplicate = second.body?.duplicate === true || second.res.status === 200;
  let cleaned = false;
  if (!ctx.params.keep) cleaned = await deleteLedgerRecord(ctx, first.id);
  if (!duplicate) {
    return fail(
      `同 id 重发没有命中幂等：第二次 ${second.res.status} ${JSON.stringify(second.body)}`,
      '看 functions/api/ledger/index.ts 的 ON CONFLICT / duplicate 分支'
    );
  }
  return ok(`首次 201、重发 ${second.res.status} 且 duplicate=${second.body?.duplicate === true}；${cleaned ? '测试流水已删除' : '测试流水保留（keep=1）'}`);
}

async function checkUnknownTask(ctx: SelftestCtx): Promise<SelftestOutcome> {
  if (ctx.params.dryRun) return previewed('会 POST 一个不存在的 task_id，验证被拦');
  const id = selftestId('selftest-unknown');
  const res = await ctx.api('/api/ledger', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ id, task_id: 'selftest_unknown_task', task_name: '自检', type: 'earning', amount: 10 }),
  });
  const body = await readJson<Record<string, unknown>>(res);
  if (res.status < 400) {
    await deleteLedgerRecord(ctx, id);
    return fail(`未知任务被放过了（${res.status}）`, '服务端必须拒绝不在 LEDGER_TASK_RULES 里的 task_id');
  }
  return ok(`未知任务被拒：${res.status} ${body?.error ?? ''}`);
}

async function checkDailyLimit(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const rule = LEDGER_TASK_RULES[ctx.params.taskId];
  if (!rule) return fail(`taskId ${ctx.params.taskId} 不在服务端规则表里`);
  if (rule.dailyLimit === undefined) return warn(`${rule.name} 没有日限，这条检查不适用`);

  const dayKey = dayKeyOf(ctx);
  const records = await fetchAllRecords(ctx);
  const usedToday = records.filter(
    (row) =>
      row.task_id === ctx.params.taskId &&
      row.status !== 'rejected' &&
      row.created_at.slice(0, 10) === dayKey
  ).length;
  if (usedToday >= rule.dailyLimit) {
    return warn(`${rule.name} 今天已用 ${usedToday}/${rule.dailyLimit}，无法复现超限（先等到明天或用别的任务）`);
  }
  if (ctx.params.dryRun) return previewed(`会连写 ${rule.dailyLimit - usedToday + 1} 次 ${rule.name}，验证第 ${rule.dailyLimit + 1} 次被拦`);

  const created: string[] = [];
  let lastStatus = 0;
  let lastBody: unknown = null;
  for (let i = usedToday; i <= rule.dailyLimit; i += 1) {
    const attempt = await createTestRecord(ctx, { amount: rule.value });
    created.push(attempt.id);
    lastStatus = attempt.res.status;
    lastBody = attempt.body;
    if (attempt.res.status >= 400) break;
  }
  if (!ctx.params.keep) {
    for (const id of created) await deleteLedgerRecord(ctx, id);
  }
  if (lastStatus < 400) {
    return fail(
      `${rule.name} 日限 ${rule.dailyLimit} 没拦住第 ${rule.dailyLimit + 1} 次（${lastStatus}）`,
      '看 functions/api/ledger/index.ts 的日限判断'
    );
  }
  return ok(`第 ${rule.dailyLimit + 1} 次被拦：${lastStatus} ${JSON.stringify(lastBody)}；测试流水已清理`);
}

async function checkApproveFlow(ctx: SelftestCtx): Promise<SelftestOutcome> {
  if (ctx.params.dryRun) return previewed('会写一条流水 → 审批通过 → 校验状态 → 删除');
  const created = await createTestRecord(ctx);
  if (!created.res.ok) return fail(`写入失败：${created.res.status}`);
  const approve = await ctx.api(`/api/ledger/${encodeURIComponent(created.id)}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ status: 'approved' }),
  });
  const records = await fetchAllRecords(ctx);
  const row = records.find((item) => item.id === created.id);
  const cleaned = ctx.params.keep ? false : await deleteLedgerRecord(ctx, created.id);
  if (!approve.ok) return fail(`审批返回 ${approve.status}`);
  if (row?.status !== 'approved') return fail(`审批后状态是 ${row?.status ?? '查不到'}，期望 approved`);
  return ok(`审批通过且状态落库为 approved${cleaned ? '，测试流水已删除' : ''}`);
}

async function checkRejectResubmit(ctx: SelftestCtx): Promise<SelftestOutcome> {
  if (ctx.params.dryRun) return previewed('会写一条流水 → 驳回（带原因）→ 重新提交 → 删除');
  const created = await createTestRecord(ctx);
  if (!created.res.ok) return fail(`写入失败：${created.res.status}`);
  const url = `/api/ledger/${encodeURIComponent(created.id)}`;
  const reject = await ctx.api(url, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ status: 'rejected', reason: '自检驳回' }),
  });
  const afterReject = (await fetchAllRecords(ctx)).find((item) => item.id === created.id);
  const resubmit = await ctx.api(url, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ status: 'pending' }),
  });
  const afterResubmit = (await fetchAllRecords(ctx)).find((item) => item.id === created.id);
  const cleaned = ctx.params.keep ? false : await deleteLedgerRecord(ctx, created.id);
  if (!reject.ok || !resubmit.ok) return fail(`驳回 ${reject.status} / 重提 ${resubmit.status}`);
  if (afterReject?.status !== 'rejected') return fail(`驳回后状态是 ${afterReject?.status ?? '查不到'}`);
  if (afterResubmit?.status !== 'pending') return fail(`重提后状态是 ${afterResubmit?.status ?? '查不到'}`);
  return ok(`驳回 → rejected、重提 → pending${cleaned ? '，测试流水已删除' : ''}`);
}

async function checkSettleIdempotent(ctx: SelftestCtx): Promise<SelftestOutcome> {
  if (ctx.params.dryRun) {
    return previewed('会连调两次 POST /api/ledger/settle；注意第一次可能按规则真补记罚款');
  }
  const first = await ctx.api('/api/ledger/settle', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: '{}',
  });
  const firstBody = await readJson<{ applied?: string[]; day?: string; family?: number; sun?: number }>(first);
  const second = await ctx.api('/api/ledger/settle', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: '{}',
  });
  const secondBody = await readJson<{ applied?: string[]; day?: string; family?: number; sun?: number }>(second);
  if (!first.ok || !second.ok) return fail(`结算返回 ${first.status} / ${second.status}`);
  const appliedAgain = secondBody?.applied?.length ?? 0;
  if (appliedAgain > 0) {
    return fail(
      `第二次结算又补记了 ${appliedAgain} 条：${secondBody?.applied?.join('、')}`,
      '结算必须幂等（固定 id + 已存在则跳过）'
    );
  }
  if (firstBody?.family !== secondBody?.family || firstBody?.sun !== secondBody?.sun) {
    return fail('两次结算的余额不一样', undefined, { first: firstBody, second: secondBody });
  }
  return ok(
    `结算幂等（day ${secondBody?.day}，第一次 applied ${firstBody?.applied?.length ?? 0} 条，第二次 0 条）`,
    { first: firstBody, second: secondBody }
  );
}

/** 客户端上报的完成数 vs 服务端口径 —— 跨端口径对账 */
async function checkClientCompletion(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const reported = clientData<{ dayKey?: string; done?: number }>(ctx.params, 'client.rules.completion');
  const dayKey = reported?.dayKey ?? dayKeyOf(ctx);
  const { startIso, endIso } = boundsOf(dayKey);
  const server = await countDayCompletions(ctx.db, startIso, endIso);
  if (!reported || typeof reported.done !== 'number') {
    return skip(`客户端没上报完成数（服务端 ${dayKey} 算出 ${server}）`);
  }
  if (reported.done !== server) {
    return fail(
      `完成数对不上：客户端 ${reported.done}，服务端 ${server}（${dayKey}）`,
      '客户端口径必须是：待审批算完成、花钱不算、按 task_id 去重、东八区当日'
    );
  }
  return ok(`完成数一致：${server}（${dayKey}）`);
}

/* --------------------------------- 注册表 --------------------------------- */

export const CORE_ITEMS: SelftestItem[] = [
  { id: 'env.bindings', name: '绑定可查询', desc: 'DB / R2 / 提醒 Worker 配置', group: 'env', side: 'server', estMs: 30, run: checkBindings },
  { id: 'env.tables', name: '关键表齐全', desc: '7 张表的建表状态', group: 'env', side: 'server', estMs: 30, run: checkTables },
  { id: 'env.migrations', name: '迁移版本', desc: 'd1_migrations 最新一条是否为 0006', group: 'env', side: 'server', estMs: 30, run: checkMigrations },
  { id: 'env.changelog', name: '版本日志已上云', desc: 'GET /api/changelog 的条数、顺序与最新版本', group: 'env', side: 'server', estMs: 80, run: checkChangelog },
  { id: 'env.cors', name: 'CORS 预检', desc: 'OPTIONS /api/ledger 的响应头', group: 'env', side: 'server', estMs: 60, run: checkCors },
  { id: 'env.notfound', name: '未知路径 404', desc: '不存在的 /api 路径的形态', group: 'env', side: 'server', estMs: 60, run: checkNotFound },
  { id: 'env.sw', name: 'Service Worker', desc: '/sw.js 是否带 push / notificationclick', group: 'env', side: 'server', estMs: 80, run: checkServiceWorker },
  { id: 'env.manifest', name: 'PWA 清单', desc: '/manifest.webmanifest 可读', group: 'env', side: 'server', estMs: 60, run: checkManifest },

  { id: 'ledger.list', name: '流水列表结构', desc: '字段、类型、id 唯一性', group: 'ledger', side: 'server', estMs: 80, run: checkLedgerList },
  { id: 'ledger.pending', name: '待审批过滤', desc: '?status=pending 只含 pending', group: 'ledger', side: 'server', estMs: 80, run: checkPendingFilter },
  { id: 'ledger.summary.shape', name: '余额接口结构', desc: 'summary 的两个数字', group: 'ledger', side: 'server', estMs: 80, run: checkSummaryShape },
  { id: 'ledger.summary.reconcile', name: '余额对账', desc: 'summary vs 按同口径重算的流水合计', group: 'ledger', side: 'server', estMs: 120, run: checkSummaryReconcile },
  { id: 'ledger.garden.split', name: '花园/家庭分流', desc: '花园前缀流水的归属', group: 'ledger', side: 'server', estMs: 80, run: checkGardenSplit },
  { id: 'ledger.write.idempotent', name: '写入幂等', desc: '同 requestId 重发必须 duplicate', group: 'ledger', side: 'server', mutates: true, danger: 'write', uses: ['dryRun', 'taskId', 'amount', 'note', 'keep'], estMs: 200, run: checkWriteIdempotent },
  { id: 'ledger.write.unknown_task', name: '未知任务被拦', desc: '不在规则表里的 task_id 必须 4xx', group: 'ledger', side: 'server', mutates: true, danger: 'write', uses: ['dryRun'], estMs: 120, run: checkUnknownTask },
  { id: 'ledger.write.daily_limit', name: '日限拦截', desc: '连写到超过 dailyLimit，最后一次必须被拒', group: 'ledger', side: 'server', mutates: true, danger: 'write', uses: ['dryRun', 'taskId', 'keep'], estMs: 400, run: checkDailyLimit },
  { id: 'ledger.approve', name: '审批链路', desc: '写 → 通过 → 状态落库 → 删除', group: 'ledger', side: 'server', mutates: true, danger: 'write', uses: ['dryRun', 'taskId', 'keep'], estMs: 250, run: checkApproveFlow },
  { id: 'ledger.reject.resubmit', name: '驳回与重提', desc: '写 → 驳回 → 重新提交 → 删除', group: 'ledger', side: 'server', mutates: true, danger: 'write', uses: ['dryRun', 'taskId', 'keep'], estMs: 250, run: checkRejectResubmit },
  { id: 'ledger.settle.idempotent', name: '日结算幂等', desc: '连调两次 settle，第二次不能补记', group: 'ledger', side: 'server', mutates: true, danger: 'write', uses: ['dryRun'], estMs: 300, run: checkSettleIdempotent },
  { id: 'ledger.client.completion', name: '完成数跨端对账', desc: '客户端上报的完成数 vs 服务端口径', group: 'ledger', side: 'server', estMs: 80, run: checkClientCompletion },
];
