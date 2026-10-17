/**
 * 自检检查项：任务规则 + 学习计划。
 *
 * 这一组的价值在「跨端口径对账」：客户端把自己实现的口径上报（data），服务端拿真实规则比。
 * 客户端不重新实现业务口径，只上报它算出来的结果 —— 两边不一致就是 bug。
 */

import {
  COMPLETION_EXCLUDED_IDS,
  DAILY_MIN_TASKS,
  DAILY_MIN_TASKS_PENALTY,
  LEDGER_TASK_RULES,
  SLEEP_DEADLINE,
  countDayCompletions,
} from '../rules';
import {
  boundsOf,
  clientData,
  dayKeyOf,
  fail,
  ok,
  previewed,
  readJson,
  skip,
  warn,
} from './helpers';
import type { SelftestCtx, SelftestItem, SelftestOutcome } from './types';

/** 家庭账本的 12 条任务：服务端规则表必须与客户端一致 */
const EXPECTED_FAMILY_TASKS: Record<string, { value: number; type: string; dailyLimit?: number }> = {
  clean_room: { value: 10, type: 'earning', dailyLimit: 2 },
  wash_dishes: { value: 5, type: 'earning', dailyLimit: 2 },
  do_laundry: { value: 15, type: 'earning', dailyLimit: 1 },
  take_out_trash: { value: 5, type: 'earning', dailyLimit: 1 },
  finish_homework: { value: 20, type: 'earning', dailyLimit: 1 },
  read_book: { value: 10, type: 'earning', dailyLimit: 2 },
  sleep_on_time: { value: 10, type: 'earning', dailyLimit: 1 },
  ipad_time: { value: -10, type: 'spending', dailyLimit: 4 },
  phone_time: { value: -10, type: 'spending', dailyLimit: 4 },
  eye_penalty: { value: -100, type: 'spending' },
  sleep_penalty: { value: -20, type: 'spending', dailyLimit: 1 },
  homework_incomplete: { value: -50, type: 'spending', dailyLimit: 1 },
};

/**
 * ISO 周标签（`2026-W42`），与服务端 SQL 的 `IYYY-"W"IW` 和客户端 dayjs isoWeek 一致。
 * 算法：本周的周四落在哪一年，就是哪一年的周；1 月 4 日所在周是第 1 周。
 */
function isoWeekLabel(date: Date): string {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const weekday = d.getUTCDay() || 7; // 周一=1 … 周日=7
  d.setUTCDate(d.getUTCDate() + 4 - weekday); // 挪到本周周四
  const year = d.getUTCFullYear();
  const yearStart = Date.UTC(year, 0, 1);
  const week = Math.ceil(((d.getTime() - yearStart) / 86_400_000 + 1) / 7);
  return `${year}-W${String(week).padStart(2, '0')}`;
}

/** 东八区某天的周标签 */
function weekLabelOf(dayKey: string): string {
  return isoWeekLabel(new Date(`${dayKey}T12:00:00.000+08:00`));
}

/* --------------------------------- 任务规则 -------------------------------- */

async function checkRuleSnapshot(): Promise<SelftestOutcome> {
  const problems: string[] = [];
  for (const [id, expected] of Object.entries(EXPECTED_FAMILY_TASKS)) {
    const rule = LEDGER_TASK_RULES[id];
    if (!rule) {
      problems.push(`${id} 缺失`);
      continue;
    }
    if (rule.value !== expected.value) problems.push(`${id} 分值 ${rule.value} ≠ ${expected.value}`);
    if (rule.type !== expected.type) problems.push(`${id} 类型 ${rule.type} ≠ ${expected.type}`);
    if ((rule.dailyLimit ?? null) !== (expected.dailyLimit ?? null)) {
      problems.push(`${id} 日限 ${rule.dailyLimit ?? '无'} ≠ ${expected.dailyLimit ?? '无'}`);
    }
  }
  if (problems.length > 0) {
    return fail(`12 条家庭任务里有 ${problems.length} 处不符：${problems.join('；')}`, '改规则要同时改服务端与客户端');
  }
  const limited = Object.values(LEDGER_TASK_RULES).filter((rule) => rule.dailyLimit !== undefined).length;
  return ok(`12 条家庭任务与服务端规则一致；全表 ${Object.keys(LEDGER_TASK_RULES).length} 条，其中 ${limited} 条有日限`);
}

async function checkSleepWindow(): Promise<SelftestOutcome> {
  const rule = LEDGER_TASK_RULES.sleep_on_time;
  if (!rule?.window) return fail('sleep_on_time 没有时间窗，22 点提醒与睡觉卡会失效');
  if (rule.window.end !== SLEEP_DEADLINE) {
    return fail(`睡觉卡窗口结束 ${rule.window.end} 与 SLEEP_DEADLINE ${SLEEP_DEADLINE} 不一致`);
  }
  return ok(`睡觉卡窗口 ${rule.window.start}-${rule.window.end}（截止与结算一致）`);
}

async function checkCompletionSql(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const dayKey = dayKeyOf(ctx);
  const { startIso, endIso } = boundsOf(dayKey);
  const viaHelper = await countDayCompletions(ctx.db, startIso, endIso);

  // 换一种写法独立算一遍：不复用 helper 的 SQL，只共用排除名单
  const placeholders = COMPLETION_EXCLUDED_IDS.map(() => '?').join(', ');
  const row = await ctx.db
    .prepare(
      `SELECT COUNT(DISTINCT task_id) AS c FROM family_ledger
        WHERE (status IS NULL OR status = 'approved')
          AND type = 'earning' AND amount > 0
          AND task_id NOT IN (${placeholders})
          AND created_at >= ? AND created_at < ?`
    )
    .bind(...COMPLETION_EXCLUDED_IDS, startIso, endIso)
    .first<{ c: number }>();

  const independent = row?.c ?? -1;
  if (viaHelper !== independent) {
    return fail(
      `两种算法结果不同：helper ${viaHelper}，独立 SQL ${independent}`,
      'DAY_COMPLETION_SQL 与排除名单可能被改歪了'
    );
  }
  return ok(`${dayKey} 完成数 ${viaHelper}（两种算法一致；待审批算完成、花钱不算、按 task_id 去重）`);
}

/** 客户端上报的任务表 vs 服务端规则表 */
async function checkClientTableDiff(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const reported = clientData<{ tasks?: Array<{ id?: string; value?: number; type?: string; dailyLimit?: number | null }> }>(
    ctx.params,
    'client.rules.table'
  );
  if (!reported?.tasks?.length) return skip('客户端没上报任务表（本地检查项 client.rules.table 未跑）');

  const problems: string[] = [];
  for (const item of reported.tasks) {
    const id = item.id;
    if (!id) continue;
    const rule = LEDGER_TASK_RULES[id];
    if (!rule) {
      problems.push(`${id} 服务端不认识`);
      continue;
    }
    if (item.value !== undefined && item.value !== rule.value) {
      problems.push(`${id} 分值 ${item.value} ≠ 服务端 ${rule.value}`);
    }
    if (item.type !== undefined && item.type !== rule.type) {
      problems.push(`${id} 类型 ${item.type} ≠ 服务端 ${rule.type}`);
    }
    const clientLimit = item.dailyLimit ?? null;
    if (clientLimit !== (rule.dailyLimit ?? null)) {
      problems.push(`${id} 日限 ${clientLimit ?? '无'} ≠ 服务端 ${rule.dailyLimit ?? '无'}`);
    }
  }
  if (problems.length > 0) {
    return fail(
      `客户端任务表与服务端有 ${problems.length} 处不一致：${problems.join('；')}`,
      '两端规则表必须逐条一致，否则会出现「一边让打卡、一边说超限」'
    );
  }
  return ok(`客户端上报的 ${reported.tasks.length} 条任务与服务端逐条一致`);
}

/** 客户端上报的周标签 vs 服务端算法 */
async function checkClientWeek(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const reported = clientData<{ label?: string }>(ctx.params, 'client.rules.week');
  const expected = weekLabelOf(dayKeyOf(ctx));
  if (!reported?.label) return skip(`客户端没上报周标签（服务端算出 ${expected}）`);
  if (reported.label !== expected) {
    return fail(
      `周标签对不上：客户端 ${reported.label}，服务端 ${expected}`,
      '必须与 SQL 的 IYYY-"W"IW 一致（周四定年、1 月 4 日所在周为第 1 周）'
    );
  }
  return ok(`周标签一致：${expected}`);
}

/** 客户端上报的常量 vs 服务端常量 */
async function checkClientPenalty(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const reported = clientData<{
    dailyMinTasks?: number;
    dailyMinTasksPenalty?: number;
    sleepPenaltyAmount?: number;
    pointsPerYuan?: number;
    welcomeBonus?: number;
  }>(ctx.params, 'client.rules.penalty');
  if (!reported) return skip('客户端没上报罚款常量（本地检查项 client.rules.penalty 未跑）');

  const sleepPenalty = Math.abs(LEDGER_TASK_RULES.sleep_penalty?.value ?? 20);
  const expected: Array<[string, number, number | undefined]> = [
    ['每日最少任务数', DAILY_MIN_TASKS, reported.dailyMinTasks],
    ['任务不足罚款', DAILY_MIN_TASKS_PENALTY, reported.dailyMinTasksPenalty],
    ['睡觉罚款', sleepPenalty, reported.sleepPenaltyAmount],
  ];
  const problems = expected
    .filter(([, server, client]) => client !== undefined && client !== server)
    .map(([name, server, client]) => `${name} 客户端 ${client} ≠ 服务端 ${server}`);
  if (problems.length > 0) {
    return fail(problems.join('；'), '罚款金额写死在两端，改一处必须改另一处');
  }
  return ok(`阈值与罚款一致：${DAILY_MIN_TASKS} 个任务 / -${DAILY_MIN_TASKS_PENALTY} / -${sleepPenalty}`);
}

/* --------------------------------- 学习计划 -------------------------------- */

interface PlanRow {
  id?: string;
  subject?: string;
  task_name?: string;
  target?: number;
  current?: number;
  week_label?: string;
}

async function checkPlanList(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const week = ctx.params.weekLabel ?? weekLabelOf(dayKeyOf(ctx));
  const res = await ctx.api(`/api/plans?week=${encodeURIComponent(week)}`);
  if (!res.ok) return fail(`GET /api/plans?week=${week} 返回 ${res.status}`);
  const rows = await readJson<PlanRow[]>(res);
  if (!Array.isArray(rows)) return fail('计划接口返回的不是数组');
  const broken = rows.filter((row) => typeof row.subject !== 'string' || typeof row.target !== 'number');
  if (broken.length > 0) return fail(`${broken.length} 条计划字段不全`);
  const noWeek = await ctx.api('/api/plans');
  if (noWeek.status !== 400) return fail(`不带 week 参数返回 ${noWeek.status}，期望 400`);
  return ok(`${week} 有 ${rows.length} 条计划，字段完整；缺 week 参数正确返回 400`);
}

async function checkPlanInvalidWeek(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const res = await ctx.api('/api/plans?week=selftest-bogus-week');
  const rows = await readJson<PlanRow[]>(res);
  if (res.status >= 500) return fail(`非法周标签把服务端打崩了：${res.status}`);
  if (Array.isArray(rows) && rows.length > 0) {
    return fail(`非法周标签返回了 ${rows.length} 条数据`, '查询必须严格按 week_label 过滤');
  }
  return ok(`非法周标签返回 ${res.status} 且没有数据`);
}

async function checkPlanClamp(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const week = ctx.params.weekLabel ?? weekLabelOf(dayKeyOf(ctx));
  const rows = await readJson<PlanRow[]>(await ctx.api(`/api/plans?week=${encodeURIComponent(week)}`));
  const plan = Array.isArray(rows) ? rows.find((row) => typeof row.id === 'string') : undefined;
  if (!plan?.id) return warn(`${week} 没有可用的计划行（先去周计划页初始化一次）`);
  const target = Number(plan.target ?? 0);
  const original = Number(plan.current ?? 0);
  if (ctx.params.dryRun) return previewed(`会把进度写成 target+5（${target + 5}），验证被夹回 ${target}，然后还原成 ${original}`);

  const overshoot = await ctx.api(`/api/plans/${encodeURIComponent(plan.id)}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ current: target + 5 }),
  });
  const body = await readJson<{ current?: number }>(overshoot);
  const clamped = body?.current;
  await ctx.api(`/api/plans/${encodeURIComponent(plan.id)}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ current: original }),
  });
  if (!overshoot.ok) return fail(`更新计划返回 ${overshoot.status}`);
  if (clamped !== target) {
    return fail(`越界进度没被夹住：写入 ${target + 5} 得到 ${clamped}，期望 ${target}`, '见 functions/api/plans/[id].ts 的 clampCurrent');
  }
  return ok(`越界进度被夹回 ${target}（原值 ${original} 已还原）`);
}

async function checkPlanCreateIdempotent(ctx: SelftestCtx): Promise<SelftestOutcome> {
  const week = ctx.params.weekLabel ?? weekLabelOf(dayKeyOf(ctx));
  const beforeRaw = await readJson<PlanRow[]>(await ctx.api(`/api/plans?week=${encodeURIComponent(week)}`));
  const before = Array.isArray(beforeRaw) ? beforeRaw : [];
  const count = before.length;
  if (count === 0) return warn(`${week} 还没有计划，无法验证幂等（先去周计划页初始化）`);
  if (ctx.params.dryRun) return previewed(`会把 ${week} 现有的 ${count} 条按原样再 POST 一次，验证条数不变`);

  // 幂等键是唯一索引 (week_label, task_name) + INSERT OR IGNORE，
  // 所以必须用「该周已有的 task_name」再发一次才算验证幂等；
  // 发一条全新的 task_name 本来就应该新增一行。
  const items = before.map((row) => ({
    subject: row.subject ?? '',
    task_name: row.task_name ?? '',
    target: typeof row.target === 'number' ? row.target : 0,
  }));
  const res = await ctx.api('/api/plans', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ week_label: week, items }),
  });
  const after = await readJson<PlanRow[]>(await ctx.api(`/api/plans?week=${encodeURIComponent(week)}`));
  const afterCount = Array.isArray(after) ? after.length : -1;
  if (!res.ok && res.status !== 201) return fail(`初始化返回 ${res.status}`);
  if (afterCount !== count) {
    return fail(
      `按原样重复初始化把条数从 ${count} 变成 ${afterCount}`,
      '唯一索引 (week_label, task_name) + INSERT OR IGNORE 应当幂等'
    );
  }
  return ok(`按原样重复初始化 ${week} 后条数仍为 ${count}（唯一键 week_label+task_name 生效）`);
}

export const RULES_ITEMS: SelftestItem[] = [
  { id: 'rules.snapshot', name: '12 条任务规则', desc: '服务端规则表的分值/类型/日限', group: 'rules', side: 'server', estMs: 10, run: checkRuleSnapshot },
  { id: 'rules.sleep_window', name: '睡觉卡时间窗', desc: '窗口结束与 SLEEP_DEADLINE 一致', group: 'rules', side: 'server', estMs: 10, run: checkSleepWindow },
  { id: 'rules.completion.sql', name: '完成数 SQL 自洽', desc: 'helper 与独立 SQL 两种算法一致', group: 'rules', side: 'server', estMs: 60, run: checkCompletionSql },
  { id: 'rules.client.table', name: '任务表跨端对账', desc: '客户端上报的任务表 vs 服务端', group: 'rules', side: 'server', estMs: 20, run: checkClientTableDiff },
  { id: 'rules.client.week', name: '周标签跨端对账', desc: '客户端算的周标签 vs 服务端', group: 'rules', side: 'server', estMs: 20, run: checkClientWeek },
  { id: 'rules.client.penalty', name: '罚款常量跨端对账', desc: '阈值与金额两端一致', group: 'rules', side: 'server', estMs: 20, run: checkClientPenalty },

  { id: 'plans.list', name: '计划列表', desc: '字段完整 + 缺 week 参数 400', group: 'plans', side: 'server', uses: ['weekLabel'], estMs: 100, run: checkPlanList },
  { id: 'plans.invalid_week', name: '非法周标签', desc: '不返回别周的数据、不崩', group: 'plans', side: 'server', estMs: 80, run: checkPlanInvalidWeek },
  { id: 'plans.clamp', name: '进度夹取值', desc: '越界进度必须夹回 target 并还原', group: 'plans', side: 'server', mutates: true, danger: 'write', uses: ['dryRun', 'weekLabel'], estMs: 200, run: checkPlanClamp },
  { id: 'plans.create.idempotent', name: '初始化幂等', desc: '重复初始化同一周不新增行', group: 'plans', side: 'server', mutates: true, danger: 'write', uses: ['dryRun', 'weekLabel'], estMs: 200, run: checkPlanCreateIdempotent },
];
