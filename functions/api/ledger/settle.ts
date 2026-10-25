/**
 * 日结算接口（v1.30）。
 * 路由：**POST** /api/ledger/settle → { family, sun, applied, day }
 *
 * ## 为什么要有这个接口
 * Cloudflare Pages 没有 scheduled handler（本项目只有 functions/api/maintenance/orphans.ts
 * 这类手动维护接口），所以「必须任务没做扣 10」「本周任务缺次扣 10」与「22:00 还没打卡睡觉扣 20」
 * 不可能在半夜自动执行，只能在**下次打开页面时补记**（需求方案「风险」一节）。补记有两个硬要求：
 *
 *  1. **幂等靠固定 id，不靠任何额外状态**：系统记录的 id 全部固定 ——
 *     `seed_welcome_bonus` / `sleep_penalty_<东八区 YYYY-MM-DD>` /
 *     `must_miss_<taskId>_<日期>` / `weekly_miss_<taskId>_<周一日期>_<第几次>`，
 *     一律 INSERT OR IGNORE —— 同一天调多少次都只落一条，并发/重试天然安全。
 *  2. **created_at 回填到被结算那一天的正午**（东八区）：罚款若按真实时间落库，
 *     隔天补记的记录会落在第二天，污染按 created_at 过滤的「当日完成数」。
 *
 * ## 结算哪一天（settleDay）
 *  - 现在 ≥ 22:00（SLEEP_DEADLINE）→ **今天**（这一天已经过完，可以判罚款）
 *  - 否则 → **昨天**（最近一个已经过完的东八区日）
 *
 * 关键点：**只有「确实已经过完的那一天」才判罚款**。若按字面「今天没打卡就扣」，
 * 早上首次打开页面时今天必然还没打卡（打卡数恒为 0），等于每天无条件扣 10 ——
 * 那是把「没做完当天的事要扣分」做反了。此语义已与 Lead 确认（选 C，v2.10 沿用）。
 *
 * 请求体的 `date`（'YYYY-MM-DD'）是**测试用**覆盖项：显式指定「被结算的那一天」。
 *
 * ## 不追溯开户之前
 * 账本里此前**一条流水都没有**时（这次调用就是开户那一刻），或 settleDay 早于账本最早一条
 * 流水所在东八区日时，一律不判罚款：不能给「账本还不存在」的日子开罚单。老账号不受影响
 * （最早流水是很久以前，settleDay 必然 ≥ 它）。
 *
 * ## 路由冲突
 * `/api/ledger/<id>` 是动态路由（functions/api/ledger/[id].ts 导出 onRequestPatch /
 * onRequestDelete），字面量 'settle' 会落进它的匹配范围。所以本文件**只导出 onRequestPost**：
 * 与动态路由的方法集完全不重叠，冲突面为零（不要在这里加 PATCH/DELETE）。
 */

import {
  COMPLETION_EXCLUDED_SQL_LIST,
  DAILY_MUST_TASK_IDS,
  LEDGER_TASK_RULES,
  MUST_PENALTY_SINCE_DAY,
  MUST_PENALTY_SINCE_WEEK,
  SLEEP_DEADLINE,
  WEEKLY_TASK_RULES,
  beijingClock,
  beijingDayBoundsOf,
  beijingWeekdayOf,
  countTaskRecords,
  isPastBeijingTime,
  mustMissRecordId,
  sleepPenaltyRecordId,
  weekBoundsOf,
  weeklyMissRecordId,
} from '../../_lib/rules';
import { LEDGER_SUMMARY_SQL } from './summary';

interface Env {
  DB: D1Database;
}

/** 开户礼金：全新账号一次性 +100 */
const SEED_TASK_ID = 'seed_welcome_bonus';
/** 按时睡觉打卡（判定「有没有按时睡」的依据） */
const SLEEP_TASK_ID = 'sleep_on_time';
/** 睡觉罚款 */
const SLEEP_PENALTY_TASK_ID = 'sleep_penalty';
/** v2.10 必须任务没做（每件一条记录，逐件 −10） */
const MUST_MISS_TASK_ID = 'must_task_miss_penalty';
/** v2.10 周任务缺次（缺一次一条记录，−10/次） */
const WEEKLY_MISS_TASK_ID = 'weekly_task_miss_penalty';

const DAY_KEY_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const CN_OFFSET_MS = 8 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

/** 'YYYY-MM-DD' 且是真实存在的日期（挡掉 2026-02-31 这种） */
function isRealDayKey(value: string): boolean {
  if (!DAY_KEY_PATTERN.test(value)) return false;
  const ms = Date.parse(`${value}T00:00:00.000+08:00`);
  if (!Number.isFinite(ms)) return false;
  // 反解回东八区日期，必须与原值一致（2 月 31 日会被 JS 归一成 3 月初）
  return new Date(ms + CN_OFFSET_MS).toISOString().slice(0, 10) === value;
}

/** 东八区某天 00:00 的 UTC 毫秒数（调用方保证 dayKey 合法） */
function dayStartMs(dayKey: string): number {
  return Date.parse(`${dayKey}T00:00:00.000+08:00`);
}

/** 东八区「昨天」的 dayKey */
function previousDayKey(dayKey: string): string {
  return new Date(dayStartMs(dayKey) - DAY_MS + CN_OFFSET_MS).toISOString().slice(0, 10);
}

/**
 * 写一条服务端系统记录（金额 / 类型 / 名字一律取服务端规则，客户端改不动）。
 * INSERT OR IGNORE：id 撞了就什么都不做，返回是否**真的插进去了**。
 */
async function insertSystemRecord(
  db: D1Database,
  input: { id: string; taskId: string; createdAt: string; note?: string }
): Promise<boolean> {
  const rule = LEDGER_TASK_RULES[input.taskId];
  if (!rule) return false;
  const result = await db
    .prepare(
      `INSERT OR IGNORE INTO family_ledger (id, task_id, task_name, type, amount, note, image_url, status, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
    )
    .bind(
      input.id,
      input.taskId,
      rule.name,
      rule.type,
      rule.value,
      input.note ?? null,
      null,
      'approved',
      input.createdAt
    )
    .run();
  return Boolean(result.meta.changes);
}

/** 某一天是否已经有这个 task_id 的记录（被驳回的不算；NULL 状态算历史已入账） */
async function hasRecordForDay(
  db: D1Database,
  taskId: string,
  startIso: string,
  endIso: string,
  approvedOnly: boolean
): Promise<boolean> {
  const statusClause = approvedOnly
    ? "(status IS NULL OR status = 'approved')"
    : "(status IS NULL OR status != 'rejected')";
  const row = await db
    .prepare(
      `SELECT COUNT(*) AS c FROM family_ledger
       WHERE task_id = ? AND ${statusClause} AND created_at >= ? AND created_at < ?`
    )
    .bind(taskId, startIso, endIso)
    .first<{ c: number }>();
  return (row?.c ?? 0) > 0;
}

/** 日结算：开户礼金 + 睡觉罚款 + 每日不足任务数罚款，全部幂等 */
export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  try {
    const now = new Date();
    const todayKey = beijingClock(now).dayKey;

    // 请求体可选：前端可以不传 body。解析失败一律按「没带」处理。
    let body: Record<string, unknown> = {};
    try {
      const parsed: unknown = await request.json();
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        body = parsed as Record<string, unknown>;
      }
    } catch {
      body = {};
    }

    const requestedDate = body.date;
    const yesterdayKey = previousDayKey(todayKey);
    let settleDay: string;
    if (requestedDate !== undefined) {
      if (typeof requestedDate !== 'string' || !isRealDayKey(requestedDate)) {
        return Response.json({ error: 'date 必须是合法的 YYYY-MM-DD' }, { status: 400 });
      }
      if (requestedDate > todayKey) {
        return Response.json({ error: '不能结算未来的日期' }, { status: 400 });
      }
      // 「今天/昨天」之外的日期不给补：再往前就是给账本补历史罚单，
      // 而这个接口没有鉴权，挡在两天内能把「凭空造罚款」的空间压到最小。
      if (requestedDate < yesterdayKey) {
        return Response.json({ error: '只能补结算今天或昨天' }, { status: 400 });
      }
      settleDay = requestedDate;
    } else {
      settleDay = isPastBeijingTime(SLEEP_DEADLINE, now) ? todayKey : previousDayKey(todayKey);
    }

    const { startIso, endIso, noonIso } = beijingDayBoundsOf(settleDay);
    // 只有「确实已经过完的那一天」才判罚款：settleDay 是过去某天，或今天且已过 22:00。
    // 显式传 date=今天 但还没到 22:00 时同样不判 —— 这一天孩子还有机会完成任务 / 打卡。
    const dayIsOver = settleDay < todayKey || isPastBeijingTime(SLEEP_DEADLINE, now);

    const applied: string[] = [];

    /* 不追溯开户之前的罚款：账本里此前一条流水都没有时（这次调用就是开户那一刻），
       不能给「账本还不存在」的日子开罚单；settleDay 早于账本最早一条流水所在日时同样不判。
       老账号不受影响 —— 最早流水是很久以前，settleDay 必然 ≥ 它。
       ⚠️ 必须在写 seed 之前查：seed 一落库，账本的「第一天」就变成今天了。 */
    const firstRow = await env.DB.prepare(
      'SELECT MIN(created_at) AS firstAt FROM family_ledger'
    ).first<{ firstAt: string | null }>();
    const firstMs = firstRow?.firstAt ? Date.parse(firstRow.firstAt) : NaN;
    const accountFirstDay = Number.isFinite(firstMs)
      ? beijingClock(new Date(firstMs)).dayKey
      : null;
    const canPenalize = accountFirstDay !== null && settleDay >= accountFirstDay;

    /* ① 开户礼金：只给全新账号 —— 既没有 seed 记录，也没有任何真实用户流水。
       「真实用户流水」= 除三条系统记录以外的任何一行（有花园流水的老账号同样不算新账号）。
       少了这道判断，老账号也会凭空多 100。 */
    const seedState = await env.DB.prepare(
      `SELECT
         (SELECT COUNT(*) FROM family_ledger WHERE task_id = ?) AS seeds,
         (SELECT COUNT(*) FROM family_ledger WHERE task_id NOT IN (${COMPLETION_EXCLUDED_SQL_LIST})) AS realRows`
    )
      .bind(SEED_TASK_ID)
      .first<{ seeds: number; realRows: number }>();
    if ((seedState?.seeds ?? 0) === 0 && (seedState?.realRows ?? 0) === 0) {
      // 礼金是「此刻开户」这一件事，时间戳就是现在（不回填；回填只针对罚款）
      if (
        await insertSystemRecord(env.DB, {
          id: SEED_TASK_ID,
          taskId: SEED_TASK_ID,
          createdAt: now.toISOString(),
        })
      ) {
        applied.push(SEED_TASK_ID);
      }
    }

    if (dayIsOver && canPenalize) {
      /* ② 睡觉罚款：结算日没有「已通过」的按时睡觉打卡 → -20。
         先查当天有没有 sleep_penalty（含家长手工记的那条），再 INSERT OR IGNORE 固定 id：
         两道一起用才不会和手工记录重复扣（家长在 22:00 后手工记过，日结算就不再记）。 */
      const sleptOnTime = await hasRecordForDay(env.DB, SLEEP_TASK_ID, startIso, endIso, true);
      const hasSleepPenalty = await hasRecordForDay(
        env.DB,
        SLEEP_PENALTY_TASK_ID,
        startIso,
        endIso,
        false
      );
      if (!sleptOnTime && !hasSleepPenalty) {
        if (
          await insertSystemRecord(env.DB, {
            id: sleepPenaltyRecordId(settleDay),
            taskId: SLEEP_PENALTY_TASK_ID,
            createdAt: noonIso,
            note: `结算日 ${settleDay}：当日没有按时睡觉打卡`,
          })
        ) {
          applied.push(sleepPenaltyRecordId(settleDay));
        }
      }

      /* ③ v2.10 必须任务没做 → 逐件 −10。
         判定口径与睡觉罚款一致：结算日没有「已通过」的打卡就算没做。
         sleep_on_time **不在这里** —— 它由上面的 sleep_penalty（−20）负责，
         两边都算就成了「一晚扣两次」。
         老口径「当日完成数不足 5 件扣 10」从 v2.10 起不再结算（家长反馈会和新规则重复扣），
         规则与历史记录仍保留在 rules.ts 里。
         ⚠️ 生效日之前的日子一律跳过：补结算「规则上线前的那一天」时，新任务在账本里
         必然一条记录都没有 —— 不设这道门就是无差别误扣。 */
      if (settleDay >= MUST_PENALTY_SINCE_DAY) {
        for (const mustTaskId of DAILY_MUST_TASK_IDS) {
          const didIt = await hasRecordForDay(env.DB, mustTaskId, startIso, endIso, true);
          if (didIt) continue;
          const recordId = mustMissRecordId(mustTaskId, settleDay);
          const taskName = LEDGER_TASK_RULES[mustTaskId]?.name ?? mustTaskId;
          if (
            await insertSystemRecord(env.DB, {
              id: recordId,
              taskId: MUST_MISS_TASK_ID,
              createdAt: noonIso,
              note: `结算日 ${settleDay}：没做「${taskName}」`,
            })
          ) {
            applied.push(recordId);
          }
        }
      }

      /* ④ v2.10 本周任务缺次 → −10/次，只在**这一周过完**时结算（settleDay 是周日）。
         洗头一周 3 次、剪指甲一周 1 次；数这一周里「已通过」的记录条数，缺几次记几笔。
         补记边界与日结算一致：只结算最近一个过完的日子 —— 周一打开 App 会补上周日，
         覆盖绝大部分情况；连着一周不打开 App 就补不上那几周的周任务，这是现有
         「开页面才补记」机制的固有局限，不是本次引入的。 */
      if (beijingWeekdayOf(settleDay) === 0) {
        const week = weekBoundsOf(settleDay);
        if (week.weekStartKey >= MUST_PENALTY_SINCE_WEEK) {
          for (const { taskId, target } of WEEKLY_TASK_RULES) {
            const done = await countTaskRecords(env.DB, taskId, week.startIso, week.endIso);
            const miss = Math.max(0, target - done);
            const taskName = LEDGER_TASK_RULES[taskId]?.name ?? taskId;
            for (let nth = 1; nth <= miss; nth++) {
              const recordId = weeklyMissRecordId(taskId, week.weekStartKey, nth);
              if (
                await insertSystemRecord(env.DB, {
                  id: recordId,
                  taskId: WEEKLY_MISS_TASK_ID,
                  createdAt: noonIso,
                  note: `本周（${week.weekStartKey} 起）「${taskName}」只做了 ${done}/${target} 次`,
                })
              ) {
                applied.push(recordId);
              }
            }
          }
        }
      }
    }

    // 结算后的余额（与 GET /api/ledger/summary 同一个 SQL，口径不会漂）
    const row = await env.DB.prepare(LEDGER_SUMMARY_SQL).first<{
      family: number | null;
      sun: number | null;
    }>();

    return Response.json({
      family: row?.family ?? 0,
      sun: row?.sun ?? 0,
      applied,
      // 本次结算的是哪一天（前端拿它做「当天已结算过就不再调」的节流键）
      day: settleDay,
    });
  } catch (error) {
    // 别空手吞：结算里任何一步失败都要能在 Workers 日志里看到原因
    console.error('settle ledger failed', error);
    return Response.json({ error: '结算失败' }, { status: 500 });
  }
};
