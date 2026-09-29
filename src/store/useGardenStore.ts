import { create } from 'zustand';
import {
  GARDEN_TASKS,
  GARDEN_BADGES,
  GARDEN_POEMS,
  GARDEN_CHINESE_PRACTICES,
  GARDEN_SHOP_ITEMS,
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
  /** 今日已背会的古诗 id（自然日维度去重） */
  todayPoemIds: string[];
  /** todayPoemIds 所属的自然日 */
  poemDate: string;
  /** 今日语文练习打卡次数（练习 id -> 次数） */
  chineseSteps: Record<string, number>;
  /** chineseSteps 所属的自然日 */
  chineseDate: string;
  /** 最近一次「照顾花园」的自然日 */
  lastCareDate: string | null;

  /** 初始化（从 localStorage 恢复或使用默认） */
  init: () => void;
  /** 完成任务：增加阳光积分，更新完成状态 */
  completeTask: (taskId: string) => void;
  /** 重置今日任务 */
  resetTasks: () => void;
  /** 背会一首古诗：同日同诗只计一次；返回是否计入 */
  recitePoem: (poemId: string) => boolean;
  /** 语文练习打卡一次：计一次花园任务完成；返回是否计入 */
  completeChineseStep: (practiceId: string) => boolean;
  /** 照顾花园（按自然日去重）；返回今天是否新计入一天 */
  careForGarden: () => boolean;
  /** 用阳光积分兑换商城物品 */
  buyItem: (itemId: string) => ShopBuyResult;
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
  | 'todayPoemIds'
  | 'poemDate'
  | 'chineseSteps'
  | 'chineseDate'
  | 'lastCareDate'
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
  gardenCareDays: number;
  lastCareDate: string;
}

/** 计算累计数据时所需的现有字段 */
type CounterSource = Pick<
  GardenStore,
  | 'balance'
  | 'streakDays'
  | 'completedCount'
  | 'totalCompleted'
  | 'lastActiveDate'
  | 'gardenCareDays'
  | 'lastCareDate'
>;

/**
 * 计算完成一次花园活动后的累计数据。
 * countToday=false 表示今日任务数已经计过（不重复 +1，避免今日进度超过任务总数）。
 * 任意一天在花园里活动即算作一次「照顾花园」，同一天只记一次。
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
    gardenCareDays: source.lastCareDate === today ? source.gardenCareDays : source.gardenCareDays + 1,
    lastCareDate: today,
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
    todayPoemIds: state.todayPoemIds,
    poemDate: state.poemDate,
    chineseSteps: state.chineseSteps,
    chineseDate: state.chineseDate,
    lastCareDate: state.lastCareDate,
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
  todayPoemIds: [],
  poemDate: '',
  chineseSteps: {},
  chineseDate: '',
  lastCareDate: null,

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

    const next: PersistedGarden = {
      balance,
      tasks: saved.tasks ?? GARDEN_TASKS,
      badges: resolveBadges(saved.badges ?? GARDEN_BADGES, {
        totalCompleted,
        balance,
        streakDays,
        poemCount,
        gardenCareDays,
      }),
      streakDays,
      completedCount: toSafeCount(saved.completedCount),
      totalCompleted,
      lastActiveDate: saved.lastActiveDate ?? null,
      poemCount,
      gardenCareDays,
      ownedItems: toSafeStringArray(saved.ownedItems),
      todayPoemIds: samePoemDay ? toSafeStringArray(saved.todayPoemIds) : [],
      poemDate: today,
      chineseSteps: sameChineseDay ? toSafeCountRecord(saved.chineseSteps) : {},
      chineseDate: today,
      lastCareDate: typeof saved.lastCareDate === 'string' ? saved.lastCareDate : null,
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
      lastCareDate: stats.lastCareDate,
      // 跨天后今日打卡记录自动失效
      todayPoemIds: state.poemDate === today ? state.todayPoemIds : [],
      poemDate: today,
      chineseSteps: state.chineseDate === today ? state.chineseSteps : {},
      chineseDate: today,
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
      lastCareDate: stats.lastCareDate,
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
      lastCareDate: stats.lastCareDate,
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
    if (state.lastCareDate === today) return false;

    const gardenCareDays = state.gardenCareDays + 1;
    const next: PersistedGarden = {
      ...toPersisted(state),
      gardenCareDays,
      lastCareDate: today,
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

  resetTasks: () => {
    // 仅重置今日任务与今日计数，保留余额、累计数、连续天数、勋章、已购物品与今日打卡记录
    const state = get();
    const next: PersistedGarden = {
      ...toPersisted(state),
      tasks: GARDEN_TASKS,
      completedCount: 0,
    };
    set(next);
    saveState(next);
  },
}));
