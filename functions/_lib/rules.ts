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
  /** 允许客户端传金额的例外：服务端只做范围校验（目前只有老余额迁移用） */
  clientAmount?: { min: number; max: number };
}

/** 家庭账本任务（对应 src/config/familyRules.ts） */
const FAMILY_TASK_RULES: Record<string, ServerTaskRule> = {
  clean_room: { name: '整理房间', type: 'earning', value: 10, dailyLimit: 2 },
  wash_dishes: { name: '洗碗', type: 'earning', value: 5, dailyLimit: 2 },
  do_laundry: { name: '洗衣服', type: 'earning', value: 15, dailyLimit: 1 },
  take_out_trash: { name: '倒垃圾', type: 'earning', value: 5, dailyLimit: 1 },
  finish_homework: { name: '按时完成作业', type: 'earning', value: 20, dailyLimit: 1 },
  read_book: { name: '课外阅读30分钟', type: 'earning', value: 10, dailyLimit: 2 },
  // 只有 19:00-21:30 之间能打卡；晚于 21:30 说明没按时睡，由家长记 sleep_penalty
  sleep_on_time: {
    name: '按时睡觉',
    type: 'earning',
    value: 10,
    dailyLimit: 1,
    window: { start: '19:00', end: '21:30' },
  },

  ipad_time: { name: '看iPad 30分钟', type: 'spending', value: -10, dailyLimit: 4 },
  phone_time: { name: '玩手机 30分钟', type: 'spending', value: -10, dailyLimit: 4 },

  eye_penalty: { name: '视力下降1度', type: 'spending', value: -100 },
  // 与 sleep_on_time 的窗口对齐：晚于 21:30 才算没按时作息
  sleep_penalty: { name: '未按时作息(晚于21:30)', type: 'spending', value: -20, dailyLimit: 1 },
  homework_incomplete: { name: '作业未完成', type: 'spending', value: -50, dailyLimit: 1 },
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

/** 全部已知任务规则 */
export const LEDGER_TASK_RULES: Record<string, ServerTaskRule> = {
  ...FAMILY_TASK_RULES,
  ...GARDEN_TASK_RULES,
};

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
