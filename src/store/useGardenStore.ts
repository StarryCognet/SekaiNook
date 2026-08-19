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
  /** 初始化（从 localStorage 恢复或使用默认） */
  init: () => void;
  /** 完成任务：增加阳光积分，更新完成状态 */
  completeTask: (taskId: string) => void;
  /** 重置今日任务 */
  resetTasks: () => void;
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
function saveState(state: Partial<GardenStore>): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}

export const useGardenStore = create<GardenStore>((set, get) => ({
  balance: 0,
  tasks: GARDEN_TASKS,
  badges: GARDEN_BADGES,
  streakDays: 1,
  completedCount: 0,

  init: () => {
    const saved = loadState();
    set({
      balance: saved.balance ?? 0,
      tasks: saved.tasks ?? GARDEN_TASKS,
      badges: saved.badges ?? GARDEN_BADGES,
      streakDays: saved.streakDays ?? 1,
      completedCount: saved.completedCount ?? 0,
    });
  },

  completeTask: (taskId) => {
    const { tasks, balance, completedCount } = get();
    const task = tasks.find((t) => t.id === taskId);
    if (!task || task.done) return;

    const updatedTasks = tasks.map((t) =>
      t.id === taskId ? { ...t, done: true, completedAt: new Date().toISOString() } : t
    );
    const newBalance = balance + task.reward;
    const newCount = completedCount + 1;

    // 更新勋章：根据完成情况解锁
    const updatedBadges = get().badges.map((b) => {
      if (b.earned) return b;
      if (b.id === 'sunrise' && newCount >= 1) return { ...b, earned: true };
      if (b.id === 'gardener' && newCount >= 10) return { ...b, earned: true };
      if (b.id === 'sun_rich' && newBalance >= 500) return { ...b, earned: true };
      return b;
    });

    const next = {
      balance: newBalance,
      tasks: updatedTasks,
      badges: updatedBadges,
      completedCount: newCount,
    };
    set(next);
    saveState(next);
  },

  resetTasks: () => {
    const next = { tasks: GARDEN_TASKS, completedCount: 0 };
    set(next);
    saveState(next);
  },
}));