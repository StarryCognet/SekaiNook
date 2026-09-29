import { create } from 'zustand';
import {
  GARDEN_TASKS,
  GARDEN_BADGES,
  GARDEN_POEMS,
  GARDEN_CHINESE_PRACTICES,
  GARDEN_SHOP_ITEMS,
  GARDEN_MAX_DECOR,
} from '../config/garden';
import type { GardenTask, Badge } from '../types/garden';

const STORAGE_KEY = 'sekainook_garden_state';

/** 与「今日任务」联动的任务 id：背诗 / 语文练习完成时同步点亮 */
const POEM_TASK_ID = 'poem';
const CHINESE_TASK_ID = 'chinese';

/** 商城兑换结果 */
export type ShopBuyResult = 'ok' | 'owned' | 'insufficient' | 'unknown';

interface GardenStore {
  balance: number;
  tasks: GardenTask[];
  badges: Badge[];
  streakDays: number;
  completedCount: number;
  /** 累计完成任务数（跨天累计，不随每日重置清零） */
  totalCompleted: number;
  /** 最近一次完成任务的日期（YYYY-MM-DD，本地时区） */
  lastActiveDate: string | null;
  /** 累计背会古诗首数（跨天累计） */
  poemCount: number;
  /** 累计照顾花园天数（按自然日去重） */
  gardenCareDays: number;
  /** 已拥有的商城物品 id */
  ownedItems: string[];
  /** 正戴着的头像框 id（null = 没戴） */
  equippedAvatar: string | null;
  /** 正挂着的称号 id（null = 没挂） */
  equippedTitle: string | null;
  /** 正挂在花园里的装饰 id（最多 GARDEN_MAX_DECOR 件，先挂的排在前面） */
  equippedDecor: string[];
  /** 今日已背会的古诗 id（自然日维度去重） */
  todayPoemIds: string[];
  /** todayPoemIds 所属的自然日 */
  poemDate: string;
  /** 今日语文练习打卡次数（练习 id -> 次数） */
  chineseSteps: Record<string, number>;
  /** chineseSteps 所属的自然日 */
  chineseDate: string;
  /** 今日实际入账的阳光（商城花掉的不算，跨天自动归零） */
  todayEarned: number;
  /** todayEarned 所属的自然日 */
  todayEarnedDate: string;
  /** 最近一次浇水的自然日：浇水的「今天浇过没有」只看它，完成任务不再顶掉 */
  lastWaterDate: string | null;
  /**
   * 最近一次「照顾花园」的自然日（完成任务或浇水都算），只用于 gardenCareDays 按自然日去重。
   * 「今天浇过水没有」由 lastWaterDate 单独管，两者分开维护。
   */
  lastGardenedDate: string | null;
  /** tasks / completedCount 所属的自然日（跨天要自动归零） */
  tasksDate: string;

  /** 初始化（从 localStorage 恢复或使用默认） */
  init: () => void;
  /** 完成任务：增加阳光积分，更新完成状态 */
  completeTask: (taskId: string) => void;
  /** 背会一首古诗：同日同诗只计一次；返回是否计入 */
  recitePoem: (poemId: string) => boolean;
  /** 语文练习打卡一次：计一次花园任务完成；返回是否计入 */
  completeChineseStep: (practiceId: string) => boolean;
  /** 照顾花园（按自然日去重）；返回今天是否新计入一天 */
  careForGarden: () => boolean;
  /** 用阳光积分兑换商城物品 */
  buyItem: (itemId: string) => ShopBuyResult;
  /**
   * 戴上 / 挂上已经拥有的物品（按物品 category 落到对应字段）。
   * 没拥有返回 'owned'（不生效），物品不存在返回 'unknown'。
   */
  equipItem: (itemId: string) => 'ok' | 'owned' | 'unknown';
  /** 取下 / 摘下物品（没戴着也安全，什么也不做） */
  unequipItem: (itemId: string) => void;
}

/** 需要持久化的字段（完整写入，避免局部保存覆盖其它字段） */
type PersistedGarden = Pick<
  GardenStore,
  | 'balance'
  | 'tasks'
  | 'badges'
  | 'streakDays'
  | 'completedCount'
  | 'totalCompleted'
  | 'lastActiveDate'
  | 'poemCount'
  | 'gardenCareDays'
  | 'ownedItems'
  | 'equippedAvatar'
  | 'equippedTitle'
  | 'equippedDecor'
  | 'todayPoemIds'
  | 'poemDate'
  | 'chineseSteps'
  | 'chineseDate'
  | 'todayEarned'
  | 'todayEarnedDate'
  | 'lastWaterDate'
  | 'lastGardenedDate'
  | 'tasksDate'
>;

/** 本地日期键（YYYY-MM-DD） */
function toDateKey(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

/** 今日日期键（供页面判断「今天是否已打卡」） */
export function todayKey(): string {
  return toDateKey(new Date());
}

/** 安全读取非负整数：兼容旧 state 的缺失字段与脏数据，避免 undefined / NaN */
function toSafeCount(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) && value > 0 ? Math.floor(value) : 0;
}

/** 安全读取字符串数组（兼容旧 state） */
function toSafeStringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string') : [];
}

/** 安全读取「可能为空的字符串」（兼容旧 state）：空串与脏数据一律当作没设 */
function toSafeId(value: unknown): string | null {
  return typeof value === 'string' && value ? value : null;
}

/** 安全读取「每项打卡次数」映射（兼容旧 state） */
function toSafeCountRecord(value: unknown): Record<string, number> {
  if (!value || typeof value !== 'object') return {};
  const result: Record<string, number> = {};
  for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
    const count = toSafeCount(item);
    if (count > 0) result[key] = count;
  }
  return result;
}

/** 计算完成一次任务后的连续天数：昨天完成过则 +1，今天已完成则不变，否则重新计为 1 */
function nextStreak(lastActiveDate: string | null, streakDays: number, today: string): number {
  if (!lastActiveDate) return 1;
  if (lastActiveDate === today) return streakDays;
  const yesterday = toDateKey(new Date(Date.now() - 86400000));
  return lastActiveDate === yesterday ? streakDays + 1 : 1;
}

/** 依据累计数据判定勋章：满足条件即永久获得（不因重置失去） */
function resolveBadges(
  badges: Badge[],
  stats: {
    totalCompleted: number;
    balance: number;
    streakDays: number;
    poemCount: number;
    gardenCareDays: number;
  }
): Badge[] {
  const unlocked: Record<string, boolean> = {
    sunrise: stats.totalCompleted >= 1,
    gardener: stats.totalCompleted >= 10,
    streak3: stats.streakDays >= 3,
    week_champ: stats.streakDays >= 7,
    poet: stats.poemCount >= 10,
    plant_warrior: stats.gardenCareDays >= 7,
    sun_rich: stats.balance >= 500,
  };
  return badges.map((b) => (unlocked[b.id] ? { ...b, earned: true } : b));
}

/** 一次活动完成后的累计数据 */
interface CompletionStats {
  balance: number;
  streakDays: number;
  completedCount: number;
  totalCompleted: number;
  lastActiveDate: string;
  todayEarned: number;
  gardenCareDays: number;
  lastGardenedDate: string;
}

/** 计算累计数据时所需的现有字段 */
type CounterSource = Pick<
  GardenStore,
  | 'balance'
  | 'streakDays'
  | 'completedCount'
  | 'totalCompleted'
  | 'lastActiveDate'
  | 'todayEarned'
  | 'todayEarnedDate'
  | 'gardenCareDays'
  | 'lastGardenedDate'
>;

/**
 * 计算完成一次花园活动后的累计数据。
 * countToday=false 表示今日任务数已经计过（不重复 +1，避免今日进度超过任务总数）。
 * 任意一天在花园里活动即算作一次「照顾花园」，同一天只记一次（按 lastGardenedDate 去重）。
 * todayEarned 只累加入账的奖励，商城兑换（buyItem）不走这里，所以「花掉的」不会冲掉「赚到的」。
 */
function nextCompletionStats(
  source: CounterSource,
  reward: number,
  today: string,
  countToday: boolean
): CompletionStats {
  return {
    balance: source.balance + reward,
    streakDays: nextStreak(source.lastActiveDate, source.streakDays, today),
    completedCount: countToday ? source.completedCount + 1 : source.completedCount,
    totalCompleted: source.totalCompleted + 1,
    lastActiveDate: today,
    todayEarned: (source.todayEarnedDate === today ? source.todayEarned : 0) + reward,
    gardenCareDays:
      source.lastGardenedDate === today ? source.gardenCareDays : source.gardenCareDays + 1,
    lastGardenedDate: today,
  };
}

/** 取出全部需要持久化的字段 */
function toPersisted(state: GardenStore): PersistedGarden {
  return {
    balance: state.balance,
    tasks: state.tasks,
    badges: state.badges,
    streakDays: state.streakDays,
    completedCount: state.completedCount,
    totalCompleted: state.totalCompleted,
    lastActiveDate: state.lastActiveDate,
    poemCount: state.poemCount,
    gardenCareDays: state.gardenCareDays,
    ownedItems: state.ownedItems,
    equippedAvatar: state.equippedAvatar,
    equippedTitle: state.equippedTitle,
    equippedDecor: state.equippedDecor,
    todayPoemIds: state.todayPoemIds,
    poemDate: state.poemDate,
    chineseSteps: state.chineseSteps,
    chineseDate: state.chineseDate,
    todayEarned: state.todayEarned,
    todayEarnedDate: state.todayEarnedDate,
    lastWaterDate: state.lastWaterDate,
    lastGardenedDate: state.lastGardenedDate,
    tasksDate: state.tasksDate,
  };
}

/** 从 localStorage 读取状态 */
function loadState(): Partial<GardenStore> {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

/** 保存状态到 localStorage */
function saveState(state: PersistedGarden): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}

export const useGardenStore = create<GardenStore>((set, get) => ({
  balance: 0,
  tasks: GARDEN_TASKS,
  badges: GARDEN_BADGES,
  streakDays: 0,
  completedCount: 0,
  totalCompleted: 0,
  lastActiveDate: null,
  poemCount: 0,
  gardenCareDays: 0,
  ownedItems: [],
  equippedAvatar: null,
  equippedTitle: null,
  equippedDecor: [],
  todayPoemIds: [],
  poemDate: '',
  chineseSteps: {},
  chineseDate: '',
  todayEarned: 0,
  todayEarnedDate: '',
  lastWaterDate: null,
  lastGardenedDate: null,
  tasksDate: '',

  init: () => {
    const saved = loadState();
    const today = toDateKey(new Date());
    const balance = toSafeCount(saved.balance);
    const streakDays = toSafeCount(saved.streakDays);
    const totalCompleted = toSafeCount(saved.totalCompleted);
    const poemCount = toSafeCount(saved.poemCount);
    const gardenCareDays = toSafeCount(saved.gardenCareDays);
    // 旧 state 没有这些字段时视为「今天还没有打卡记录」
    const samePoemDay = saved.poemDate === today;
    const sameChineseDay = saved.chineseDate === today;
    // 今日任务跨天要自动归零：旧存档没有 tasksDate，一律当作「不是今天」，
    // 于是第二天打开就是崭新的一天（以前会一直停在昨天「全部完成」的状态）
    const sameTaskDay = saved.tasksDate === today;
    const sameEarnedDay = saved.todayEarnedDate === today;
    // 浇水与照顾花园是两个口径：lastWaterDate 缺失（老存档）时当作「今天还没浇水」，
    // 于是孩子当天还能浇一次；gardenCareDays 的去重基准改用 lastGardenedDate。
    const lastWaterDate = toSafeId(saved.lastWaterDate);
    // 这次改造前的存档只有 lastCareDate（那时任务完成也写它）：拿它当「最近一次照顾花园」的兜底
    const legacyCareDate = (saved as Record<string, unknown>).lastCareDate;
    const lastGardenedDate = toSafeId(saved.lastGardenedDate) ?? toSafeId(legacyCareDate);
    // 老存档没有「今日入账」这个字段：拿今天已完成任务的奖励和兜底一次，
    // 免得刚升级的那一天记录页显示 0（之后的每一笔入账会继续累加在上面）
    const legacyEarned =
      sameTaskDay && Array.isArray(saved.tasks)
        ? saved.tasks.reduce((sum, task) => sum + (task?.done ? toSafeCount(task.reward) : 0), 0)
        : 0;

    const next: PersistedGarden = {
      balance,
      tasks: sameTaskDay ? (saved.tasks ?? GARDEN_TASKS) : GARDEN_TASKS,
      badges: resolveBadges(saved.badges ?? GARDEN_BADGES, {
        totalCompleted,
        balance,
        streakDays,
        poemCount,
        gardenCareDays,
      }),
      streakDays,
      completedCount: sameTaskDay ? toSafeCount(saved.completedCount) : 0,
      totalCompleted,
      lastActiveDate: saved.lastActiveDate ?? null,
      poemCount,
      gardenCareDays,
      ownedItems: toSafeStringArray(saved.ownedItems),
      equippedAvatar: toSafeId(saved.equippedAvatar),
      equippedTitle: toSafeId(saved.equippedTitle),
      equippedDecor: toSafeStringArray(saved.equippedDecor).slice(0, GARDEN_MAX_DECOR),
      todayPoemIds: samePoemDay ? toSafeStringArray(saved.todayPoemIds) : [],
      poemDate: today,
      chineseSteps: sameChineseDay ? toSafeCountRecord(saved.chineseSteps) : {},
      chineseDate: today,
      todayEarned: sameEarnedDay ? toSafeCount(saved.todayEarned) : legacyEarned,
      todayEarnedDate: today,
      lastWaterDate,
      lastGardenedDate,
      tasksDate: today,
    };
    set(next);
    // 回写一次：旧用户缺失的新字段被补成默认值，后续读取不再有 undefined
    saveState(next);
  },

  completeTask: (taskId) => {
    const state = get();
    const task = state.tasks.find((t) => t.id === taskId);
    if (!task || task.done) return;

    const today = toDateKey(new Date());
    const stats = nextCompletionStats(state, task.reward, today, true);
    const next: PersistedGarden = {
      ...toPersisted(state),
      balance: stats.balance,
      tasks: state.tasks.map((t) =>
        t.id === taskId ? { ...t, done: true, completedAt: new Date().toISOString() } : t
      ),
      badges: resolveBadges(state.badges, {
        totalCompleted: stats.totalCompleted,
        balance: stats.balance,
        streakDays: stats.streakDays,
        poemCount: state.poemCount,
        gardenCareDays: stats.gardenCareDays,
      }),
      streakDays: stats.streakDays,
      completedCount: stats.completedCount,
      totalCompleted: stats.totalCompleted,
      lastActiveDate: stats.lastActiveDate,
      gardenCareDays: stats.gardenCareDays,
      lastGardenedDate: stats.lastGardenedDate,
      todayEarned: stats.todayEarned,
      todayEarnedDate: today,
      // 跨天后今日打卡记录自动失效
      todayPoemIds: state.poemDate === today ? state.todayPoemIds : [],
      poemDate: today,
      chineseSteps: state.chineseDate === today ? state.chineseSteps : {},
      chineseDate: today,
      // 今日任务这一批属于今天（跨天判断的基准）
      tasksDate: today,
    };
    set(next);
    saveState(next);
  },

  recitePoem: (poemId) => {
    const state = get();
    const poem = GARDEN_POEMS.find((p) => p.id === poemId);
    if (!poem) return false;

    const today = toDateKey(new Date());
    const todayPoemIds = state.poemDate === today ? state.todayPoemIds : [];
    // 同一天同一首诗只计一次
    if (todayPoemIds.includes(poemId)) return false;

    const poemTaskDone = state.tasks.find((t) => t.id === POEM_TASK_ID)?.done ?? false;
    const stats = nextCompletionStats(state, poem.reward, today, !poemTaskDone);
    const poemCount = state.poemCount + 1;
    const next: PersistedGarden = {
      ...toPersisted(state),
      balance: stats.balance,
      // 与「今日任务・背一首古诗」同步，避免同一天重复领奖
      tasks: poemTaskDone
        ? state.tasks
        : state.tasks.map((t) =>
            t.id === POEM_TASK_ID ? { ...t, done: true, completedAt: new Date().toISOString() } : t
          ),
      badges: resolveBadges(state.badges, {
        totalCompleted: stats.totalCompleted,
        balance: stats.balance,
        streakDays: stats.streakDays,
        poemCount,
        gardenCareDays: stats.gardenCareDays,
      }),
      streakDays: stats.streakDays,
      completedCount: stats.completedCount,
      totalCompleted: stats.totalCompleted,
      lastActiveDate: stats.lastActiveDate,
      poemCount,
      gardenCareDays: stats.gardenCareDays,
      lastGardenedDate: stats.lastGardenedDate,
      todayEarned: stats.todayEarned,
      todayEarnedDate: today,
      todayPoemIds: [...todayPoemIds, poemId],
      poemDate: today,
      chineseSteps: state.chineseDate === today ? state.chineseSteps : {},
      chineseDate: today,
    };
    set(next);
    saveState(next);
    return true;
  },

  completeChineseStep: (practiceId) => {
    const state = get();
    const practice = GARDEN_CHINESE_PRACTICES.find((p) => p.id === practiceId);
    if (!practice) return false;

    const today = toDateKey(new Date());
    const steps = state.chineseDate === today ? state.chineseSteps : {};
    const done = steps[practiceId] ?? 0;
    // 每天每项练习的打卡次数上限
    if (done >= practice.timesPerDay) return false;

    const chineseTaskDone = state.tasks.find((t) => t.id === CHINESE_TASK_ID)?.done ?? false;
    const stats = nextCompletionStats(state, practice.reward, today, !chineseTaskDone);
    const next: PersistedGarden = {
      ...toPersisted(state),
      balance: stats.balance,
      tasks: chineseTaskDone
        ? state.tasks
        : state.tasks.map((t) =>
            t.id === CHINESE_TASK_ID ? { ...t, done: true, completedAt: new Date().toISOString() } : t
          ),
      badges: resolveBadges(state.badges, {
        totalCompleted: stats.totalCompleted,
        balance: stats.balance,
        streakDays: stats.streakDays,
        poemCount: state.poemCount,
        gardenCareDays: stats.gardenCareDays,
      }),
      streakDays: stats.streakDays,
      completedCount: stats.completedCount,
      totalCompleted: stats.totalCompleted,
      lastActiveDate: stats.lastActiveDate,
      gardenCareDays: stats.gardenCareDays,
      lastGardenedDate: stats.lastGardenedDate,
      todayEarned: stats.todayEarned,
      todayEarnedDate: today,
      todayPoemIds: state.poemDate === today ? state.todayPoemIds : [],
      poemDate: today,
      chineseSteps: { ...steps, [practiceId]: done + 1 },
      chineseDate: today,
    };
    set(next);
    saveState(next);
    return true;
  },

  careForGarden: () => {
    const state = get();
    const today = toDateKey(new Date());
    // 「今天浇过水没有」只看浇水自己的记录：做完任务不再把浇水顶掉（以前会白点）
    if (state.lastWaterDate === today) return false;

    // 任务与浇水都算「照顾花园」，但同一天只累加一天（「植物战士」勋章口径不变）
    const gardenCareDays =
      state.lastGardenedDate === today ? state.gardenCareDays : state.gardenCareDays + 1;
    const next: PersistedGarden = {
      ...toPersisted(state),
      lastWaterDate: today,
      lastGardenedDate: today,
      gardenCareDays,
      badges: resolveBadges(state.badges, {
        totalCompleted: state.totalCompleted,
        balance: state.balance,
        streakDays: state.streakDays,
        poemCount: state.poemCount,
        gardenCareDays,
      }),
    };
    set(next);
    saveState(next);
    return true;
  },

  buyItem: (itemId) => {
    const state = get();
    const item = GARDEN_SHOP_ITEMS.find((i) => i.id === itemId);
    if (!item) return 'unknown';
    if (state.ownedItems.includes(itemId)) return 'owned';
    if (state.balance < item.cost) return 'insufficient';

    const next: PersistedGarden = {
      ...toPersisted(state),
      balance: state.balance - item.cost,
      ownedItems: [...state.ownedItems, itemId],
    };
    set(next);
    saveState(next);
    return 'ok';
  },

  equipItem: (itemId) => {
    const state = get();
    const item = GARDEN_SHOP_ITEMS.find((i) => i.id === itemId);
    if (!item) return 'unknown';
    // 没买过就不让用：商城页只给已拥有的物品显示「戴上 / 挂上」
    if (!state.ownedItems.includes(itemId)) return 'owned';

    const next: PersistedGarden = { ...toPersisted(state) };
    if (item.category === 'avatar') {
      // 头像框一次只戴一个：换上新的就把旧的换下来
      next.equippedAvatar = itemId;
    } else if (item.category === 'title') {
      // 称号同理，一次只挂一个
      next.equippedTitle = itemId;
    } else {
      // 装饰可以同时挂好几件：先去掉可能重复的同一件，再挂到最后
      const rest = state.equippedDecor.filter((id) => id !== itemId);
      // 挂满 GARDEN_MAX_DECOR 件时，替换掉最早挂上的那件（数组头部）
      const kept =
        rest.length >= GARDEN_MAX_DECOR ? rest.slice(rest.length - (GARDEN_MAX_DECOR - 1)) : rest;
      next.equippedDecor = [...kept, itemId];
    }
    set(next);
    saveState(next);
    return 'ok';
  },

  unequipItem: (itemId) => {
    const state = get();
    const item = GARDEN_SHOP_ITEMS.find((i) => i.id === itemId);
    // 不认识的物品直接忽略，页面不会因此崩
    if (!item) return;

    const next: PersistedGarden = { ...toPersisted(state) };
    if (item.category === 'avatar') {
      if (state.equippedAvatar === itemId) next.equippedAvatar = null;
    } else if (item.category === 'title') {
      if (state.equippedTitle === itemId) next.equippedTitle = null;
    } else {
      next.equippedDecor = state.equippedDecor.filter((id) => id !== itemId);
    }
    set(next);
    saveState(next);
  },
}));
