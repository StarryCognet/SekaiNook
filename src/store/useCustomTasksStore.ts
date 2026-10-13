/**
 * 自定义任务列表（本地存档，**不加表**：线上 D1 没有 migration 执行通道）。
 *
 * v1.30 需求 5：点「添加任务」只把任务写进这份列表，**不入账**；
 * 打卡完成时才写流水（预置任务与家长加的直接到账，孩子自己加的走待审批）。
 *
 * 正确性一律以服务端为准：同名当日只能打一次卡、当日条数 ≥20、
 * 当日正分累计 ≥50 这些闸门都在服务端（409），本地只做置灰提示。
 */

import { create } from 'zustand';
import { countTodaySubmissions } from '../utils/taskRules';
import type { LedgerRecord, TaskType } from '../types/family';

/** 本地存档键（契约 §4 写死，不得改名） */
export const CUSTOM_TASKS_KEY = 'sekainook_custom_tasks_v1';

/**
 * 自定义任务打卡统一执行 id（契约 §2）：名称由客户端带、amount 由客户端带，
 * type 由服务端按 amount 符号覆盖；未知 task_id 一律 403，所以绝不能自造 id。
 */
export const USER_TASK_EXEC_ID = 'user_task_exec';

/** 两条预置学习任务：各自独立 task_id、各自日限 1、打卡即时到账，且不占 50 分自定义额度 */
export const PRESET_TASK_IDS = ['custom:english_words10', 'custom:poem2'] as const;

/** 单条任务的分值上限（服务端 clientAmount 夹取范围是 -200~200） */
const MAX_TASK_VALUE = 200;

/** 三条系统流水不计入「今日完成数」（契约 §3） */
const SYSTEM_TASK_IDS: readonly string[] = [
  'seed_welcome_bonus',
  'daily_min_tasks_penalty',
  'sleep_penalty',
];

/** 自定义任务（契约 §4，字段名不得改） */
export interface CustomTask {
  id: string;
  name: string;
  /** 完成可得（正）/ 需扣（负） */
  value: number;
  type: 'earning' | 'spending';
  createdBy: 'parent' | 'child';
  createdAt: string;
  kind: 'preset' | 'custom';
  /** 默认 true：每天可再打卡一次 */
  repeatDaily: boolean;
}

/** 新增一条任务需要的信息（id / createdAt 由 store 生成） */
export interface CustomTaskInput {
  name: string;
  value: number;
  type: TaskType;
  createdBy: 'parent' | 'child';
  /** 缺省 'custom' */
  kind?: 'preset' | 'custom';
  /** 缺省 true */
  repeatDaily?: boolean;
  /** 预置任务用固定 id；不给就按 createdBy 生成 custom_/wish_ */
  id?: string;
}

/** 两条预置任务的定义（id 与 task_id 同名，见契约 §2） */
const PRESET_TASKS: readonly CustomTask[] = [
  {
    id: PRESET_TASK_IDS[0],
    name: '十个英语单词',
    value: 10,
    type: 'earning',
    // §4 只有 parent / child 两个取值：预置任务按「家长加的」算，打卡即时到账
    createdBy: 'parent',
    createdAt: '',
    kind: 'preset',
    repeatDaily: true,
  },
  {
    id: PRESET_TASK_IDS[1],
    name: '两首古诗',
    value: 10,
    type: 'earning',
    createdBy: 'parent',
    createdAt: '',
    kind: 'preset',
    repeatDaily: true,
  },
];

/** 本机存档的完整结构（一个键里放任务、完成日、以及被删掉的预置任务） */
interface StoredPayload {
  tasks: CustomTask[];
  doneDate: Record<string, string>;
  /** 被删掉的预置任务 id：删了就别再自动加回来 */
  removedPresets: string[];
}

const BEIJING_OFFSET_MS = 8 * 60 * 60 * 1000;

/**
 * 东八区日历天（YYYY-MM-DD）。
 * 服务端的日限 / 判重 / 结算都按东八区，本地记「今天完成过」也必须同一个时区，
 * 否则晚上 8 点后本机把今天算成明天，打卡按钮会莫名复活。
 */
export function beijingDayKey(now: Date = new Date()): string {
  const shifted = new Date(now.getTime() + BEIJING_OFFSET_MS);
  return `${shifted.getUTCFullYear()}-${String(shifted.getUTCMonth() + 1).padStart(2, '0')}-${String(
    shifted.getUTCDate()
  ).padStart(2, '0')}`;
}

/**
 * 任务名规范化：trim + 折叠空白 + 截断 30 —— 与服务端同一套。
 * 服务端判重按规范化后的名字，本地置灰也必须按同一个结果认，否则会「看着能点、点了 409」。
 */
export function normalizeTaskName(name: string): string {
  return name.trim().replace(/\s+/g, ' ').slice(0, 30);
}

/** 存进来的一条任务是不是能用的（存档被手改过也不能把页面搞崩） */
function toTask(value: unknown): CustomTask | null {
  if (!value || typeof value !== 'object') return null;
  const raw = value as Partial<CustomTask>;
  if (typeof raw.id !== 'string' || raw.id === '') return null;
  if (typeof raw.name !== 'string' || raw.name === '') return null;
  if (typeof raw.value !== 'number' || !Number.isFinite(raw.value)) return null;
  const type: TaskType = raw.type === 'spending' ? 'spending' : 'earning';
  const value2 = type === 'earning' ? Math.abs(raw.value) : -Math.abs(raw.value);
  return {
    id: raw.id,
    name: raw.name,
    value: value2,
    type,
    createdBy: raw.createdBy === 'child' ? 'child' : 'parent',
    createdAt: typeof raw.createdAt === 'string' ? raw.createdAt : new Date().toISOString(),
    kind: raw.kind === 'preset' ? 'preset' : 'custom',
    repeatDaily: raw.repeatDaily !== false,
  };
}

/** 读本机存档；坏数据一律当空，绝不让首页白屏 */
function readStored(): StoredPayload {
  const empty: StoredPayload = { tasks: [], doneDate: {}, removedPresets: [] };
  let raw: string | null = null;
  try {
    raw = localStorage.getItem(CUSTOM_TASKS_KEY);
  } catch {
    return empty;
  }
  if (!raw) return empty;
  try {
    const parsed: unknown = JSON.parse(raw);
    // 容错：最早想直接存数组，读到数组也认
    const tasksRaw = Array.isArray(parsed)
      ? parsed
      : (parsed as Partial<StoredPayload> | null)?.tasks;
    const tasks = (Array.isArray(tasksRaw) ? tasksRaw : [])
      .map(toTask)
      .filter((t): t is CustomTask => t !== null);
    const doneDateRaw = Array.isArray(parsed)
      ? {}
      : ((parsed as Partial<StoredPayload> | null)?.doneDate ?? {});
    const doneDate: Record<string, string> = {};
    if (doneDateRaw && typeof doneDateRaw === 'object') {
      for (const [id, day] of Object.entries(doneDateRaw)) {
        if (typeof day === 'string') doneDate[id] = day;
      }
    }
    const removedRaw = Array.isArray(parsed)
      ? []
      : ((parsed as Partial<StoredPayload> | null)?.removedPresets ?? []);
    const removedPresets = (Array.isArray(removedRaw) ? removedRaw : []).filter(
      (x): x is string => typeof x === 'string'
    );
    return { tasks, doneDate, removedPresets };
  } catch {
    return empty;
  }
}

/** 写本机存档（存不了也不影响这一次使用） */
function writeStored(payload: StoredPayload): void {
  try {
    localStorage.setItem(CUSTOM_TASKS_KEY, JSON.stringify(payload));
  } catch {
    /* 本机存储不可用：退化成只在内存里生效 */
  }
}

/** 本地任务 id：家长 `custom_<ts>`、孩子 `wish_<ts>`（契约 §2）；同一毫秒撞了往后挪 */
function nextTaskId(createdBy: 'parent' | 'child', tasks: readonly CustomTask[]): string {
  const prefix = createdBy === 'child' ? 'wish_' : 'custom_';
  let stamp = Date.now();
  while (tasks.some((t) => t.id === `${prefix}${stamp}`)) stamp += 1;
  return `${prefix}${stamp}`;
}

interface CustomTasksState {
  tasks: CustomTask[];
  /** 每个任务最后一次完成的东八区日期（YYYY-MM-DD） */
  doneDate: Record<string, string>;
  addTask: (input: CustomTaskInput) => CustomTask;
  removeTask: (id: string) => void;
  /** 幂等：重复调用不会产生重复项，也不覆盖已有（含用户改过 / 删过的） */
  ensurePresets: () => void;
  markDone: (id: string) => void;
  isDoneToday: (id: string) => boolean;
}

/** 自定义任务列表（本地存档） */
export const useCustomTasksStore = create<CustomTasksState>((set, get) => {
  const restored = readStored();
  /** 被删掉的预置任务：不进 state（UI 不需要），但要跟存档一起写回去 */
  let removedPresets = restored.removedPresets;

  const persist = (tasks: CustomTask[], doneDate: Record<string, string>) => {
    writeStored({ tasks, doneDate, removedPresets });
  };

  return {
    tasks: restored.tasks,
    doneDate: restored.doneDate,

    addTask: (input) => {
      const type: TaskType = input.type === 'spending' ? 'spending' : 'earning';
      const abs = Math.min(Math.max(Math.round(Math.abs(input.value)) || 1, 1), MAX_TASK_VALUE);
      const created: CustomTask = {
        id: input.id ?? nextTaskId(input.createdBy, get().tasks),
        name: normalizeTaskName(input.name) || '未命名任务',
        value: type === 'earning' ? abs : -abs,
        type,
        createdBy: input.createdBy,
        createdAt: new Date().toISOString(),
        kind: input.kind ?? 'custom',
        repeatDaily: input.repeatDaily !== false,
      };
      const tasks = [...get().tasks.filter((t) => t.id !== created.id), created];
      set({ tasks });
      persist(tasks, get().doneDate);
      return created;
    },

    removeTask: (id) => {
      const target = get().tasks.find((t) => t.id === id);
      // 预置任务删了就别再被 ensurePresets 加回来，否则删除按钮看起来是坏的
      if (target?.kind === 'preset' && !removedPresets.includes(id)) {
        removedPresets = [...removedPresets, id];
      }
      const tasks = get().tasks.filter((t) => t.id !== id);
      const doneDate = { ...get().doneDate };
      delete doneDate[id];
      set({ tasks, doneDate });
      persist(tasks, doneDate);
    },

    ensurePresets: () => {
      const tasks = [...get().tasks];
      let changed = false;
      for (const preset of PRESET_TASKS) {
        if (removedPresets.includes(preset.id)) continue;
        if (tasks.some((t) => t.id === preset.id)) continue;
        tasks.push({ ...preset, createdAt: new Date().toISOString() });
        changed = true;
      }
      if (!changed) return;
      set({ tasks });
      persist(tasks, get().doneDate);
    },

    markDone: (id) => {
      const doneDate = { ...get().doneDate, [id]: beijingDayKey() };
      set({ doneDate });
      persist(get().tasks, doneDate);
    },

    isDoneToday: (id) => {
      const day = get().doneDate[id];
      if (!day) return false;
      const task = get().tasks.find((t) => t.id === id);
      // 每天可重复的任务只认「今天」；一次性任务完成过就一直算完成
      if (task && !task.repeatDaily) return true;
      return day === beijingDayKey();
    },
  };
});

/** 预置任务（不传参时取当前 store 里的那两条） */
export function selectPresetTasks(tasks?: readonly CustomTask[]): CustomTask[] {
  const list = tasks ?? useCustomTasksStore.getState().tasks;
  return list.filter((t) => t.kind === 'preset');
}

/**
 * 今日完成数 —— 契约 §3 口径，与服务端 `daily_min_tasks_penalty` 的判断完全一致：
 * 东八区当日、无状态或已审批、`type='earning'` 且 `amount>0` 的流水，按 task_id 去重，
 * 排除三条系统记录。一天背三首诗只算 1 个任务；花钱 / 罚款不算完成。
 */
export function countDoneToday(records: readonly LedgerRecord[], now: Date = new Date()): number {
  const day = beijingDayKey(now);
  const done = new Set<string>();
  for (const record of records) {
    if (record.status && record.status !== 'approved') continue;
    if (record.type !== 'earning' || record.amount <= 0) continue;
    if (SYSTEM_TASK_IDS.includes(record.task_id)) continue;
    const at = new Date(record.created_at);
    if (Number.isNaN(at.getTime()) || beijingDayKey(at) !== day) continue;
    done.add(record.task_id);
  }
  return done.size;
}

/**
 * 这个自定义任务今天在账本里是不是已经有一条了（按钮置灰用）。
 *
 * ⚠️ 这只是省一次白跑的请求，**正确性在服务端**（同名当日第二次会 409）。
 * 预置任务有自己独立的 task_id，按 id 数（复用 `utils/taskRules` 的现有口径，含待审批、不含被驳回）；
 * 自定义任务全部写 `user_task_exec`，服务端按任务名判重 —— 本地也只能按规范化名字认。
 */
export function isRecordedToday(
  task: CustomTask,
  records: readonly LedgerRecord[],
  now: Date = new Date()
): boolean {
  if (task.kind === 'preset') return countTodaySubmissions(records, task.id, now) > 0;
  const name = normalizeTaskName(task.name);
  const today = now.toDateString();
  return records.some(
    (record) =>
      record.task_id === USER_TASK_EXEC_ID &&
      record.status !== 'rejected' &&
      normalizeTaskName(record.task_name) === name &&
      new Date(record.created_at).toDateString() === today
  );
}
