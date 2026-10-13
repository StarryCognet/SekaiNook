/**
 * 服务端任务规则：时间窗、每日次数上限、积分值 —— 服务端唯一可信来源。
 *
 * 为什么在这里再写一份：`src/config/familyRules.ts` 是**前端**配置，而公网上的任何请求
 * 都能自称任意 status / amount / task_name。服务端必须拿自己这份数据判断，
 * 两边不一致时以这里为准。改动请同时同步：
 *   - 家庭任务：src/config/familyRules.ts
 *   - 花园奖励与商城价格：src/config/garden.ts
 */

export type LedgerType = 'earning' | 'spending';

export interface ServerTaskRule {
  /** 任务显示名（服务端覆盖客户端传来的名字） */
  name: string;
  type: LedgerType;
  /** 积分值（服务端覆盖客户端传来的金额） */
  value: number;
  /** 每日提交次数上限（含待审批，不含被驳回） */
  dailyLimit?: number;
  /** 仅允许在该时间窗内打卡（东八区 HH:MM） */
  window?: { start: string; end: string };
  /** 服务端直接入账、不需要家长审批（目前只有花园里即时到账的奖励与消费） */
  autoApprove?: boolean;
  /** 允许客户端传金额的例外：服务端只做范围校验（老余额迁移、自定义任务打卡） */
  clientAmount?: { min: number; max: number };
  /**
   * 只借 clientAmount 做「客户端能不能传」的合法性校验，**金额不采纳**，仍按服务端 value。
   * 预置学习任务（custom:english_words10 / custom:poem2）用它：契约 §2 规定固定 +10，
   * 而需求方案要求保留 clientAmount 字段兼容老客户端 —— 只有「只校验不采纳」能同时成立。
   */
  clientAmountValidateOnly?: boolean;
  /**
   * 允许客户端传**任务名**的例外（只有 v1.30 的自定义任务 user_task_exec）。
   * 契约 §2 写明自定义任务「名称由客户端带」：账本里要显示孩子真正做的那件事，
   * 而不是千篇一律的「自定义任务」。服务端只做去空白 + 长度截断；
   * 金额 / 类型 / 状态仍然完全由服务端说了算，客户端改不动。
   */
  clientName?: boolean;
  /**
   * 只能由服务端接口写入（目前只有日结算 settle.ts），客户端 POST 一律 403。
   * 用途：开户礼金 / 日结算罚款这类「服务端自己生成」的记录，绝不能被客户端自己提交。
   */
  serverOnly?: boolean;
}

/** 家庭账本任务（对应 src/config/familyRules.ts） */
const FAMILY_TASK_RULES: Record<string, ServerTaskRule> = {
  clean_room: { name: '整理房间', type: 'earning', value: 10, dailyLimit: 2 },
  wash_dishes: { name: '洗碗', type: 'earning', value: 5, dailyLimit: 2 },
  do_laundry: { name: '洗衣服', type: 'earning', value: 15, dailyLimit: 1 },
  take_out_trash: { name: '倒垃圾', type: 'earning', value: 5, dailyLimit: 1 },
  finish_homework: { name: '按时完成作业', type: 'earning', value: 20, dailyLimit: 1 },
  read_book: { name: '课外阅读30分钟', type: 'earning', value: 10, dailyLimit: 2 },
  // 只有 19:00-22:00 之间能打卡；晚于 22:00 说明没按时睡，由服务端日结算记 sleep_penalty
  sleep_on_time: {
    name: '按时睡觉',
    type: 'earning',
    value: 10,
    dailyLimit: 1,
    window: { start: '19:00', end: '22:00' },
  },

  ipad_time: { name: '看iPad 30分钟', type: 'spending', value: -10, dailyLimit: 4 },
  phone_time: { name: '玩手机 30分钟', type: 'spending', value: -10, dailyLimit: 4 },

  eye_penalty: { name: '视力下降1度', type: 'spending', value: -100 },
  // 与 sleep_on_time 的窗口对齐：晚于 22:00 才算没按时作息。
  // v1.30 起这条主要由服务端日结算（functions/api/ledger/settle.ts）自动记，
  // 家长仍可手工记；两者共用同一个 task_id，所以日限对两边一起生效，不会重复扣。
  sleep_penalty: { name: '未按时作息(晚于22:00)', type: 'spending', value: -20, dailyLimit: 1 },
  homework_incomplete: { name: '作业未完成', type: 'spending', value: -50, dailyLimit: 1 },

  /* ===== v1.30 新增（见 docs/v1.30-实现契约.md §2） ===== */

  // 两条预置学习任务：打卡即到账，日限 1。分值固定 10，clientAmount 只为兼容老客户端 /
  // 未来调分：客户端传了也只做范围校验、不采纳值，实际金额仍按 value 走
  // （见 clientAmountValidateOnly 与 functions/api/ledger/index.ts 的取值分支）。
  'custom:english_words10': {
    name: '十个英语单词',
    type: 'earning',
    value: 10,
    dailyLimit: 1,
    autoApprove: true,
    clientAmount: { min: 1, max: 100 },
    clientAmountValidateOnly: true,
  },
  'custom:poem2': {
    name: '两首古诗',
    type: 'earning',
    value: 10,
    dailyLimit: 1,
    autoApprove: true,
    clientAmount: { min: 1, max: 100 },
    clientAmountValidateOnly: true,
  },
  // 自定义任务打卡的**统一执行 id**：任务名与金额由客户端带，服务端夹到 [-200, 200]。
  // 刻意**不设 autoApprove**：孩子自己提的任务若直接到账就是刷分口子（需求方案「风险」一节），
  // 一律走 pending，由家长审批。
  // ⚠️ 所有自定义任务共用这一个 task_id ⇒「同一个自定义任务每天只能打卡一次」**不能按 task_id 判**
  //（那会把整张自定义列表当成一个任务，做了英语单词就再也不能倒垃圾）。服务端按**任务名**判重，
  // 见 functions/api/ledger/index.ts 的 dailyLimit 分支；dailyLimit 在这里只是粗闸门。
  user_task_exec: {
    name: '自定义任务',
    type: 'earning',
    value: 0,
    // 粗闸门：同一个自定义任务每天只能打卡一次；真正的「按任务去重」由 index.ts 的
    // task_id + task_name 计数保证，这个数字只兜住「同一个名字连刷 20 次」。
    dailyLimit: 20,
    clientAmount: { min: -200, max: 200 },
    // 契约 §2：自定义任务的名称由客户端带（账本里显示孩子真正做的那件事）
    clientName: true,
  },
};

/** `garden_legacy` 迁移金额上限（历史本机余额最多就到这个数） */
export const GARDEN_LEGACY_MAX = 2000;

/**
 * 花园的即时奖励与消费（对应 src/config/garden.ts 的 GARDEN_TASKS / GARDEN_CHINESE_PRACTICES / GARDEN_SHOP_ITEMS）。
 * 这些是孩子自己点出来的小奖励，打卡即到账，不走家长审批；金额一律由服务端定，客户端改不动
 * （唯一例外是标了 clientAmount 的历史余额迁移）。
 */
const GARDEN_TASK_RULES: Record<string, ServerTaskRule> = {
  // 一天可以背好几首，每首 10：没有日限
  'garden:poem': { name: '背一首古诗', type: 'earning', value: 10, autoApprove: true },
  // 下面这些是「每天做一次」的日常打卡：客户端只放一次，服务端必须同样卡住（否则能连点刷分）
  'garden:chinese': { name: '语文预习 15 分钟', type: 'earning', value: 15, dailyLimit: 1, autoApprove: true },
  'garden:math': { name: '数学预习 15 分钟', type: 'earning', value: 15, dailyLimit: 1, autoApprove: true },
  'garden:reading': { name: '课外阅读 20 分钟', type: 'earning', value: 20, dailyLimit: 1, autoApprove: true },
  'garden:writing': { name: '练字 10 分钟', type: 'earning', value: 10, dailyLimit: 1, autoApprove: true },
  'garden:eyes': { name: '休息眼睛 5 分钟', type: 'earning', value: 5, dailyLimit: 1, autoApprove: true },
  'garden:sport': { name: '运动 20 分钟', type: 'earning', value: 20, dailyLimit: 1, autoApprove: true },
  'garden:chore': { name: '做一件家务', type: 'earning', value: 15, dailyLimit: 1, autoApprove: true },
  'garden:read_aloud': { name: '课文朗读', type: 'earning', value: 5, dailyLimit: 3, autoApprove: true },
  'garden:new_words': { name: '生字认读', type: 'earning', value: 5, dailyLimit: 2, autoApprove: true },
  'garden:write_words': { name: '生字书写', type: 'earning', value: 10, dailyLimit: 1, autoApprove: true },
  // 历史余额迁移（老版本把阳光记在本机 localStorage 里）：一次性搬进账本。
  // 金额由客户端传（server 端 value 只是兜底 0），但服务端卡 [0, GARDEN_LEGACY_MAX]，防止被塞大数。
  'garden_legacy': {
    name: '花园阳光迁移',
    type: 'earning',
    value: 0,
    dailyLimit: 1,
    autoApprove: true,
    clientAmount: { min: 0, max: GARDEN_LEGACY_MAX },
  },

  'garden_shop:avatar_sun': { name: '阳光头像框', type: 'spending', value: -60, autoApprove: true },
  'garden_shop:avatar_star': { name: '星星头像框', type: 'spending', value: -80, autoApprove: true },
  'garden_shop:title_poet': { name: '称号・小诗人', type: 'spending', value: -100, autoApprove: true },
  'garden_shop:title_gardener': { name: '称号・小园丁', type: 'spending', value: -120, autoApprove: true },
  'garden_shop:decor_rainbow': { name: '装饰・彩虹花架', type: 'spending', value: -150, autoApprove: true },
  'garden_shop:decor_lantern': { name: '装饰・星星灯串', type: 'spending', value: -200, autoApprove: true },
};

/* ===== v1.30 常量（值必须与前端 src/config/familyRules.ts 一致） =====
   放在 SYSTEM_TASK_RULES 之前：下面那个 map 在模块加载时就要用到 DAILY_MIN_TASKS_PENALTY。 */

/** 自定义任务打卡的**统一执行 id**（客户端提交自定义任务时用这个 task_id） */
export const EXEC_TASK_ID = 'user_task_exec';

/** 每日至少完成几个任务；不足则记一笔罚款 */
export const DAILY_MIN_TASKS = 5;

/** 每日不足任务数的罚款额（正数，实际记账为负） */
export const DAILY_MIN_TASKS_PENALTY = 10;

/**
 * 自定义任务每天最多能拿多少分（**按总额封顶，不是按次数封顶**）。
 * 两个理由，缺一不可：
 *  1. 防刷分：日限从「按 task_id」放宽成「按任务名判重」之后，换个名字就能再打一次
 *     （每次最高 +200），必须有总额闸门兜住，否则自定义任务就是无限加分口子。
 *  2. 保住需求 2 的完成数口径：按**总额**封顶而不是按**次数**封顶，「今日完成数」仍然只
 *     看去重后的任务数 —— 孩子仍有动力去做家长布置的真实任务，而不是反复造自定义任务凑数。
 * 只统计 user_task_exec；预置任务 custom:english_words10 / custom:poem2 是各自独立 id，不占这个额度。
 */
export const CUSTOM_TASK_DAILY_CAP = 50;

/**
 * 系统记录 id：既不算「今日完成数」，也不代表「真实用户流水」。
 * 只在这里登记一次，SQL 由 COMPLETION_EXCLUDED_SQL_LIST 派生，不手写第二份清单。
 */
export const COMPLETION_EXCLUDED_IDS: readonly string[] = [
  'seed_welcome_bonus',
  'daily_min_tasks_penalty',
  'sleep_penalty',
];

/** 上面那三个 id 拼成 SQL 的 IN 列表（都是代码里的字面量常量，无用户输入，不存在注入） */
export const COMPLETION_EXCLUDED_SQL_LIST = COMPLETION_EXCLUDED_IDS.map((id) => `'${id}'`).join(', ');

/**
 * 服务端自动记账的系统记录（v1.30）。它们只能由 functions/api/ledger/settle.ts 写入：
 * 标了 serverOnly，客户端 POST 会被 403 挡掉 —— 否则开户礼金就是「每天白拿 100」的刷分口子。
 * 这三条（含 sleep_penalty）同时是「今日完成数」与「真实用户流水」判定里要排除的记录，见
 * COMPLETION_EXCLUDED_IDS。
 */
const SYSTEM_TASK_RULES: Record<string, ServerTaskRule> = {
  // 开户礼金：全新账号一次性 +100（settle.ts 里判「既无 seed 记录、也无任何真实用户流水」）
  seed_welcome_bonus: {
    name: '开户礼金',
    type: 'earning',
    value: 100,
    dailyLimit: 1,
    autoApprove: true,
    serverOnly: true,
  },
  // 日结算罚款：当日去重完成数 < DAILY_MIN_TASKS 时 -10（记录 id 为 daily_penalty_<日期>）
  daily_min_tasks_penalty: {
    name: '今日完成不足 5 个任务',
    type: 'spending',
    value: -DAILY_MIN_TASKS_PENALTY,
    dailyLimit: 1,
    autoApprove: true,
    serverOnly: true,
  },
};

/** 全部已知任务规则 */
export const LEDGER_TASK_RULES: Record<string, ServerTaskRule> = {
  ...FAMILY_TASK_RULES,
  ...GARDEN_TASK_RULES,
  ...SYSTEM_TASK_RULES,
};

/** 睡觉打卡截止时刻（东八区）= sleep_on_time 窗口的结束时间，避免 22:00 在代码里写两份 */
export const SLEEP_DEADLINE = LEDGER_TASK_RULES.sleep_on_time?.window?.end ?? '22:00';

/**
 * 「今日完成数」SQL（东八区某一天的 [00:00, 次日 00:00)，两个 ? 依次是 startIso / endIso）。
 * 口径见 docs/v1.30-实现契约.md §3：东八区当日、status IS NULL 或 'approved'、
 * type='earning' 且 amount > 0 的流水，按 task_id 去重计数，并排除 COMPLETION_EXCLUDED_IDS。
 * 一天背三首诗只算 1 个任务；花钱 / 罚款不算完成。
 */
export const DAY_COMPLETION_SQL = `SELECT COUNT(DISTINCT task_id) AS c FROM family_ledger
  WHERE (status IS NULL OR status = 'approved')
    AND type = 'earning' AND amount > 0
    AND task_id NOT IN (${COMPLETION_EXCLUDED_SQL_LIST})
    AND created_at >= ? AND created_at < ?`;

/** 按上面那个口径数出某一天的「已完成任务数」 */
export async function countDayCompletions(
  db: D1Database,
  startIso: string,
  endIso: string
): Promise<number> {
  const row = await db.prepare(DAY_COMPLETION_SQL).bind(startIso, endIso).first<{ c: number }>();
  return row?.c ?? 0;
}

/** 日结算罚款的固定记录 id（东八区日期）：一天只有一条，靠 INSERT OR IGNORE 天然幂等 */
export function dailyPenaltyRecordId(dayKey: string): string {
  return `daily_penalty_${dayKey}`;
}

/** 睡觉罚款的固定记录 id（东八区日期）：一天只有一条，靠 INSERT OR IGNORE 天然幂等 */
export function sleepPenaltyRecordId(dayKey: string): string {
  return `sleep_penalty_${dayKey}`;
}

/**
 * 东八区某一天的起止时刻与**正午**（UTC ISO）。dayKey 形如 'YYYY-MM-DD'（调用方负责校验）。
 *
 * noonIso 是给「隔天补记的罚款」回填 created_at 用的：罚款若按真实时间落库，created_at
 * 会落在第二天，把第二天的「当日完成数」算错（需求方案「风险」一节明确要求回填）。
 */
export function beijingDayBoundsOf(dayKey: string): {
  startIso: string;
  endIso: string;
  noonIso: string;
} {
  const startMs = Date.parse(`${dayKey}T00:00:00.000+08:00`);
  return {
    startIso: new Date(startMs).toISOString(),
    endIso: new Date(startMs + 24 * 60 * 60 * 1000).toISOString(),
    noonIso: new Date(startMs + 12 * 60 * 60 * 1000).toISOString(),
  };
}

/** 东八区现在是否已到 / 过了 `HH:MM`（用于「到点还没打卡」判定） */
export function isPastBeijingTime(hm: string, now: Date = new Date()): boolean {
  return beijingClock(now).minutes >= toMinutes(hm);
}

/** 花园相关记录的任务 id 前缀：这些是「阳光」，不计入家庭积分 */
export const GARDEN_ID_PREFIXES: readonly string[] = ['garden:', 'garden_shop:', 'garden_legacy'];

/**
 * 花园记录的 SQL 匹配条件（`task_id LIKE ...` 的 OR 串联）。
 * 由 GARDEN_ID_PREFIXES 派生 —— **改前缀只需改上面那一处**，SQL 侧跟着变，不会漂。
 * 前缀都是代码里的字面量常量（没有用户输入），拼进 SQL 不存在注入问题。
 */
export const GARDEN_LIKE_CLAUSE = GARDEN_ID_PREFIXES.map(
  (prefix) => `task_id LIKE '${prefix}%'`
).join(' OR ');

/** 这条流水属于花园阳光（而不是家庭积分） */
export function isGardenTaskId(taskId: string): boolean {
  return GARDEN_ID_PREFIXES.some((prefix) => taskId.startsWith(prefix));
}

const CN_OFFSET_MS = 8 * 60 * 60 * 1000;

function pad(value: number): string {
  return String(value).padStart(2, '0');
}

/** 把 'HH:MM' 变成「当天第几分钟」 */
function toMinutes(hm: string): number {
  const [h, m] = hm.split(':').map(Number);
  return (Number.isFinite(h) ? h : 0) * 60 + (Number.isFinite(m) ? m : 0);
}

/**
 * 东八区墙上时钟。
 * 服务端可能是 UTC，但规则要按家里的时间判断（孩子晚上 21:31 打卡，不能因为时区变成合法）。
 */
export function beijingClock(now: Date = new Date()): { dayKey: string; minutes: number } {
  const t = new Date(now.getTime() + CN_OFFSET_MS);
  return {
    dayKey: `${t.getUTCFullYear()}-${pad(t.getUTCMonth() + 1)}-${pad(t.getUTCDate())}`,
    minutes: t.getUTCHours() * 60 + t.getUTCMinutes(),
  };
}

/** 东八区「今天」的起止时刻（UTC ISO，可直接和 created_at 比较） */
export function beijingDayBounds(now: Date = new Date()): { startIso: string; endIso: string } {
  const t = new Date(now.getTime() + CN_OFFSET_MS);
  const startUtc = Date.UTC(t.getUTCFullYear(), t.getUTCMonth(), t.getUTCDate()) - CN_OFFSET_MS;
  return {
    startIso: new Date(startUtc).toISOString(),
    endIso: new Date(startUtc + 24 * 60 * 60 * 1000).toISOString(),
  };
}

/** 时间窗校验：不在窗口内时返回给用户看的拒绝原因，通过则返回 null */
export function checkLedgerRule(rule: ServerTaskRule, now: Date = new Date()): string | null {
  if (!rule.window) return null;
  const { minutes } = beijingClock(now);
  const start = toMinutes(rule.window.start);
  const end = toMinutes(rule.window.end);
  if (minutes < start || minutes > end) {
    return `「${rule.name}」只能在 ${rule.window.start}-${rule.window.end} 之间打卡`;
  }
  return null;
}
