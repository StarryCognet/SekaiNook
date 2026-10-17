/**
 * 自检执行器：按清单顺序跑，单项超时/抛错都不拖垮整轮。
 *
 * 三条纪律：
 *   1. 客户端项服务端不跑，只把客户端回传的结果填回去（没回传就标 skip: client-side）；
 *   2. 单项 10 秒超时、整轮 45 秒预算 —— 一轮自检不能把 Function 请求拖到被掐断；
 *   3. 检查项自己负责清理，执行器只保证「一条失败不影响后面」。
 */

import { createApiHelpers, fail, normalizeParams, skip, withTimeout } from './helpers';
import { SELFTEST_GROUPS, SELFTEST_ITEMS, SELFTEST_PRESETS, SELFTEST_VERSION, clientChecks } from './registry';
import { PARAM_SPECS } from './types';
import type {
  SelftestCtx,
  SelftestEnv,
  SelftestItem,
  SelftestOutcome,
  SelftestResult,
  SelftestRunRequest,
  SelftestRunResponse,
} from './types';

/** 单项超时：超过就判失败，别让一个卡住的接口吃掉整轮 */
const ITEM_TIMEOUT_MS = 10_000;

/** 整轮预算：到点就停，把已经跑完的结果返回去 */
const TOTAL_BUDGET_MS = 45_000;

/** 数据库名（只用于响应里的环境信息，给人看的） */
const DB_NAME = 'sekainook';

function selectItems(body: SelftestRunRequest): SelftestItem[] {
  const ids = Array.isArray(body.items) ? body.items.filter((id) => typeof id === 'string') : [];
  const groups = Array.isArray(body.groups) ? body.groups.filter((id) => typeof id === 'string') : [];
  if (ids.length === 0 && groups.length === 0) return SELFTEST_ITEMS;

  const wanted = new Set(ids);
  const groupSet = new Set(groups);
  return SELFTEST_ITEMS.filter((item) => wanted.has(item.id) || groupSet.has(item.group));
}

function count(results: SelftestResult[]): SelftestRunResponse['summary'] {
  return {
    total: results.length,
    passed: results.filter((row) => row.status === 'pass').length,
    failed: results.filter((row) => row.status === 'fail').length,
    skipped: results.filter((row) => row.status === 'skip').length,
    warned: results.filter((row) => row.status === 'warn').length,
  };
}

export async function runSelftest(
  env: SelftestEnv,
  origin: string,
  body: SelftestRunRequest
): Promise<SelftestRunResponse> {
  const clientResults = Array.isArray(body.clientResults) ? body.clientResults : [];
  const params = normalizeParams(body.params, clientResults);
  const notes: string[] = [];
  const helpers = createApiHelpers(env, origin);
  const ctx: SelftestCtx = {
    env,
    db: env.DB,
    origin,
    params,
    api: helpers.api,
    worker: helpers.worker,
    password: typeof body.password === 'string' ? body.password.trim() : '',
    note: (text) => {
      if (notes.length < 50) notes.push(text);
    },
  };

  const selected = selectItems(body);
  const keepClient = body.includeClient !== false;
  const reportedClientIds = new Set(clientResults.map((row) => row?.id).filter(Boolean));
  const started = Date.now();
  const results: SelftestResult[] = [];

  for (const item of selected) {
    const t0 = Date.now();
    let outcome: SelftestOutcome;
    let reportedMs: number | null = null;

    if (item.side === 'client') {
      const reported = clientResults.find((row) => row?.id === item.id);
      if (!reported) {
        if (!keepClient) continue;
        outcome = skip('client-side');
      } else {
        outcome = { status: reported.status, detail: reported.detail ?? '', data: reported.data };
        // 客户端项的实际耗时只有前端知道（服务端只是合并），别把它覆盖成 0
        if (typeof reported.ms === 'number' && Number.isFinite(reported.ms)) reportedMs = reported.ms;
      }
    } else if (!item.run) {
      outcome = skip('这一项还没有实现');
    } else {
      try {
        outcome = await withTimeout(item.run(ctx), ITEM_TIMEOUT_MS);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        outcome = fail(`检查项抛错：${message}`, '这是自检自身的 bug，不是被测功能的问题');
      }
    }

    results.push({
      id: item.id,
      group: item.group,
      name: item.name,
      side: item.side,
      mutates: Boolean(item.mutates),
      ms: reportedMs ?? Date.now() - t0,
      ...outcome,
    });

    if (Date.now() - started > TOTAL_BUDGET_MS) {
      notes.push(`整轮超过 ${Math.round(TOTAL_BUDGET_MS / 1000)} 秒，剩下的检查项没跑`);
      break;
    }
  }

  const ranAt = new Date();
  // 客户端检查项由前端自己跑并回传；这里把「这一轮选了、但没回传结果」的项点出来，
  // 前端可以据此提示「还有 N 项客户端检查没跑」，而不是让它们静默显示成 skip。
  const clientMissing = selected
    .filter((item) => item.side === 'client' && !reportedClientIds.has(item.id))
    .map((item) => item.id);
  return {
    ranAt: ranAt.toISOString(),
    durationMs: Date.now() - started,
    env: {
      db: DB_NAME,
      origin,
      now: ranAt.toISOString(),
      worker: env.REMINDER_URL ?? '',
    },
    clientMissing,
    params: {
      dryRun: params.dryRun,
      now: params.now.toISOString(),
      simulateDone: params.simulateDone,
      dayKey: params.dayKey,
      taskId: params.taskId,
      amount: params.amount,
      note: params.note,
      weekLabel: params.weekLabel,
      audience: params.audience,
      endpoint: params.endpoint,
      channel: params.channel,
      title: params.title,
      message: params.message,
      click: params.click,
      priority: params.priority,
      force: params.force,
      keep: params.keep,
    },
    summary: count(results),
    results,
    notes,
  };
}

/** 清单（GET 用）：分组里带上各自的检查项，参数规格与预设一并给全 */
export function buildCatalog(now = new Date()) {
  return {
    version: SELFTEST_VERSION,
    generatedAt: now.toISOString(),
    groups: SELFTEST_GROUPS.map((group) => ({
      id: group.id,
      name: group.name,
      desc: group.desc,
      items: SELFTEST_ITEMS.filter((item) => item.group === group.id).map((item) => ({
        id: item.id,
        name: item.name,
        desc: item.desc,
        side: item.side,
        client: item.client ?? null,
        mutates: Boolean(item.mutates),
        danger: item.danger ?? (item.mutates ? 'write' : 'safe'),
        params: item.uses ?? [],
        estMs: item.estMs ?? 100,
      })),
    })),
    params: Object.values(PARAM_SPECS),
    presets: SELFTEST_PRESETS,
    clientChecks: clientChecks(),
  };
}
