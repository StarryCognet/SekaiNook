/**
 * 「今天还差几个任务」的判定 + 提醒发送。
 *
 * 口径**直接 import Pages Functions 的那份规则**（`functions/_lib/rules.ts`），不在这里重写 SQL。
 * 理由：提醒说「还差 2 个」而日结算算成「还差 3 个」是最难受的 bug，而两份口径只要分开写就迟早会漂。
 * 那份规则里已经包含全部细节：东八区当日、`status IS NULL 或 approved`（待审批也算）、
 * `type='earning' && amount > 0`、排除开户礼金/两种罚款、按 task_id 去重（一天背三首诗只算 1 个）。
 */
import {
  DAILY_MIN_TASKS,
  DAILY_MIN_TASKS_PENALTY,
  LEDGER_TASK_RULES,
  SLEEP_DEADLINE,
  beijingClock,
  beijingDayBoundsOf,
  countDayCompletions,
} from '../../../functions/_lib/rules';
import { sendPush, type PushChannel } from './channels';
import type { ReminderEnv } from './env';

/** 睡觉罚款金额（正数）。取自服务端规则表，避免 20 这个数字写两份 */
const SLEEP_PENALTY = Math.abs(LEDGER_TASK_RULES['sleep_penalty']?.value ?? 20);

/** 同一台设备一天只提醒一次，用 settings 表存标记（它是现成的 key/value 表，不用新建表） */
const sentKey = (dayKey: string) => `reminder_sent_${dayKey}`;

export interface ReminderPlan {
  /** 东八区日期，形如 2026-10-15 */
  dayKey: string;
  done: number;
  remaining: number;
  target: number;
  deadline: string;
  shouldSend: boolean;
  title: string;
  message: string;
  /** 完成数是「假装」的（自检 simulateDone），不是真实库里数出来的 */
  simulated?: boolean;
}

/**
 * 只算不发：今天完成几个、还差几个、该不该提醒、文案是什么。
 * `simulateDone` 只在自检里用：假装今天已完成 N 个，好把各种文案（还差 1~5 个）都验一遍，
 * 而不用真去写流水。
 */
export async function planReminder(
  env: ReminderEnv,
  now: Date = new Date(),
  simulateDone?: number
): Promise<ReminderPlan> {
  const { dayKey } = beijingClock(now);
  const { startIso, endIso } = beijingDayBoundsOf(dayKey);
  const real = await countDayCompletions(env.DB, startIso, endIso);
  const simulated = typeof simulateDone === 'number' && Number.isFinite(simulateDone);
  const done = simulated ? Math.max(0, Math.min(Math.round(simulateDone), DAILY_MIN_TASKS)) : real;
  const remaining = Math.max(0, DAILY_MIN_TASKS - done);

  return {
    dayKey,
    done,
    remaining,
    target: DAILY_MIN_TASKS,
    deadline: SLEEP_DEADLINE,
    shouldSend: remaining > 0,
    simulated,
    title: `今天还差 ${remaining} 个任务`,
    message:
      `已完成 ${done}/${DAILY_MIN_TASKS} —— ${SLEEP_DEADLINE} 前做完，不然扣 ${DAILY_MIN_TASKS_PENALTY} 分。\n` +
      `睡觉卡也别忘了：晚于 ${SLEEP_DEADLINE} 打卡要扣 ${SLEEP_PENALTY} 分。`,
  };
}

export interface RunOptions {
  trigger: 'cron' | 'manual';
  /** 手动触发：算完不发 */
  dry?: boolean;
  /** 手动触发：绕过去重、即使已完成也发（验证通道用） */
  force?: boolean;
  /** 手动触发：发一条固定测试文案（验证通道用） */
  test?: boolean;
  /** 手动触发：指定走哪条通道，用来逐条验证 */
  channel?: PushChannel;
  /** 手动触发：假装现在是这个时刻（验证跨日/时区口径用） */
  now?: Date;
  /** 手动触发：假装今天已完成 N 个任务（验证各种文案，不写库） */
  simulateDone?: number;
  /** 手动触发：自定义标题（留空用真实文案） */
  title?: string;
  /** 手动触发：自定义正文（留空用真实文案） */
  message?: string;
  /** 手动触发：只发给 parent / child 那一侧 */
  audience?: 'parent' | 'child';
  /** 手动触发：只发给这一台设备（endpoint） */
  endpoint?: string;
  /** 手动触发：优先级 1~5 */
  priority?: number;
}

export interface RunResult extends ReminderPlan {
  sent: boolean;
  skipped?: 'nothing-to-remind' | 'already-sent' | 'dry-run';
  sendStatus?: number;
  sendDetail?: string;
  /** 实际用了哪条推送通道 */
  sendChannel?: string;
}

export async function runReminder(env: ReminderEnv, opts: RunOptions): Promise<RunResult> {
  const plan = await planReminder(env, opts.now, opts.simulateDone);
  // 显式传了 dry 就听它的，没传才看环境变量（本地联调常驻 DRY_RUN=1，用 ?dry=0 单次覆盖）
  const dry = opts.dry ?? env.DRY_RUN === '1';

  // 自定义文案优先（自检里用来验证「通知内容能不能按预期变」）
  const customTitle = opts.title?.trim();
  const customMessage = opts.message?.trim();
  const effective: ReminderPlan =
    customTitle || customMessage
      ? { ...plan, title: customTitle || plan.title, message: customMessage || plan.message }
      : plan;

  if (opts.test) {
    const testPlan: ReminderPlan = {
      ...effective,
      title: customTitle || 'SekaiNook 测试通知',
      message:
        customMessage ||
        `通道打通了。以后每天 ${SLEEP_DEADLINE} 前半小时会提醒还差几个任务。`,
      shouldSend: true,
    };
    return await deliver(env, testPlan, { ...opts, force: true, dry });
  }

  if (!effective.shouldSend && !opts.force) {
    log(opts.trigger, `${effective.dayKey} 已完成 ${effective.done}/${effective.target}，不用提醒`);
    return { ...effective, sent: false, skipped: 'nothing-to-remind' };
  }

  return await deliver(env, effective, { ...opts, dry });
}

async function deliver(
  env: ReminderEnv,
  plan: ReminderPlan,
  opts: RunOptions & { dry: boolean }
): Promise<RunResult> {
  if (opts.dry) {
    log(opts.trigger, `[dry-run] 本该发送：${plan.title} / ${plan.message.replace(/\n/g, ' ')}`);
    return { ...plan, sent: false, skipped: 'dry-run' };
  }

  // cron 是 at-least-once，重复触发不能重复打扰孩子
  if (!opts.force && !(await claimDay(env, plan.dayKey))) {
    log(opts.trigger, `${plan.dayKey} 今天已经提醒过，跳过`);
    return { ...plan, sent: false, skipped: 'already-sent' };
  }

  const res = await sendPush(
    env,
    {
      title: plan.title,
      message: plan.message,
      click: env.APP_URL?.trim() || undefined,
      audience: opts.audience,
      endpoint: opts.endpoint,
      priority: opts.priority,
    },
    opts.channel
  );
  // 发送失败不该占掉「今天这一次」：通道临时挂掉（ntfy 限流、webhook 没起来）时，
  // 若把标记留着，手动 /trigger 补发也会被当成「今天已经提醒过」而静默跳过。
  // force 是绕过去重发的，本来就没抢标记，所以不能去删别人抢到的标记。
  if (!res.ok && !opts.force) {
    await releaseDay(env, plan.dayKey);
  }
  log(
    opts.trigger,
    res.ok
      ? `已发送 ${plan.dayKey}（${res.channel}）：${plan.title}（${res.status}）`
      : `发送失败 ${plan.dayKey}（${res.channel}）：${res.detail ?? res.status}`
  );
  return {
    ...plan,
    sent: res.ok,
    sendStatus: res.status,
    sendDetail: res.detail,
    sendChannel: res.channel,
  };
}

/**
 * 抢占「今天这一条」的发送权：`INSERT ... ON CONFLICT DO NOTHING` + 看 meta.changes。
 * 返回 true 表示这条是我们发的，false 表示已经被别的实例发过了。
 *
 * settings 表还没迁移时（本地空库）不该因此不发通知 —— 那样一个无关的表结构问题会静默掐掉提醒，
 * 所以出错时按「可以发」处理，并把原因写进日志。
 */
async function claimDay(env: ReminderEnv, dayKey: string): Promise<boolean> {
  try {
    const nowIso = new Date().toISOString();
    const res = await env.DB.prepare(
      'INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?) ON CONFLICT(key) DO NOTHING'
    )
      .bind(sentKey(dayKey), nowIso, nowIso)
      .run();
    return (res.meta?.changes ?? 0) > 0;
  } catch (error) {
    console.warn('claimDay failed, 按可发送处理', error);
    return true;
  }
}

function log(trigger: string, message: string): void {
  console.log(`[reminder:${trigger}] ${message}`);
}

/** 发送失败时把标记还回去（尽力而为，删不掉也只是少一次补发机会） */
async function releaseDay(env: ReminderEnv, dayKey: string): Promise<void> {
  try {
    await env.DB.prepare('DELETE FROM settings WHERE key = ?').bind(sentKey(dayKey)).run();
    console.log(`[reminder] 发送失败，已释放 ${sentKey(dayKey)} 以便补发`);
  } catch (error) {
    console.warn('releaseDay failed', error);
  }
}
