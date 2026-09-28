import { create } from 'zustand';
import { GARDEN_TASKS, GARDEN_BADGES } from '../config/garden';
import type { GardenTask, Badge } from '../types/garden';

const STORAGE_KEY = 'sekainook_garden_state';

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
  /** 初始化（从 localStorage 恢复或使用默认） */
  init: () => void;
  /** 完成任务：增加阳光积分，更新完成状态 */
  completeTask: (taskId: string) => void;
  /** 重置今日任务 */
  resetTasks: () => void;
}

/** 需要持久化的字段（完整写入，避免局部保存覆盖其它字段） */
type PersistedGarden = Pick<
  GardenStore,
  'balance' | 'tasks' | 'badges' | 'streakDays' | 'completedCount' | 'totalCompleted' | 'lastActiveDate'
>;

/** 本地日期键（YYYY-MM-DD） */
function toDateKey(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
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
  stats: { totalCompleted: number; balance: number; streakDays: number }
): Badge[] {
  const unlocked: Record<string, boolean> = {
    sunrise: stats.totalCompleted >= 1,
    gardener: stats.totalCompleted >= 10,
    streak3: stats.streakDays >= 3,
    week_champ: stats.streakDays >= 7,
    sun_rich: stats.balance >= 500,
  };
  return badges.map((b) => (unlocked[b.id] ? { ...b, earned: true } : b));
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

  init: () => {
    const saved = loadState();
    const balance = saved.balance ?? 0;
    const streakDays = saved.streakDays ?? 0;
    const totalCompleted = saved.totalCompleted ?? 0;
    set({
      balance,
      tasks: saved.tasks ?? GARDEN_TASKS,
      badges: resolveBadges(saved.badges ?? GARDEN_BADGES, { totalCompleted, balance, streakDays }),
      streakDays,
      completedCount: saved.completedCount ?? 0,
      totalCompleted,
      lastActiveDate: saved.lastActiveDate ?? null,
    });
  },

  completeTask: (taskId) => {
    const { tasks, balance, badges, completedCount, totalCompleted, streakDays, lastActiveDate } = get();
    const task = tasks.find((t) => t.id === taskId);
    if (!task || task.done) return;

    const today = toDateKey(new Date());
    const updatedTasks = tasks.map((t) =>
      t.id === taskId ? { ...t, done: true, completedAt: new Date().toISOString() } : t
    );
    const newBalance = balance + task.reward;
    const newCount = completedCount + 1;
    const newTotal = totalCompleted + 1;
    const newStreak = nextStreak(lastActiveDate, streakDays, today);

    const next: PersistedGarden = {
      balance: newBalance,
      tasks: updatedTasks,
      badges: resolveBadges(badges, { totalCompleted: newTotal, balance: newBalance, streakDays: newStreak }),
      streakDays: newStreak,
      completedCount: newCount,
      totalCompleted: newTotal,
      lastActiveDate: today,
    };
    set(next);
    saveState(next);
  },

  resetTasks: () => {
    // 仅重置今日任务与今日计数，保留余额、累计数、连续天数与已获勋章
    const { balance, badges, streakDays, totalCompleted, lastActiveDate } = get();
    const next: PersistedGarden = {
      balance,
      tasks: GARDEN_TASKS,
      badges,
      streakDays,
      completedCount: 0,
      totalCompleted,
      lastActiveDate,
    };
    set(next);
    saveState(next);
  },
}));