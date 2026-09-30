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
import type { LedgerRecord } from '../types/family';
import {
  GARDEN_LEGACY_MAX,
  GARDEN_LEGACY_TASK_ID,
  calcGardenBalance,
  createRequestId,
  fetchLedgerRecords,
  fetchLedgerSummary,
  gardenShopItemId,
  gardenShopTaskId,
  gardenTaskId,
  isGardenTaskId,
  isRejectedWriteError,
  postLedgerRecord,
} from '../api/familyLedger';

const STORAGE_KEY = 'sekainook_garden_state';

/**
 * 老数据「已迁移」标志：迁移流水全部落账（或被服务端拒绝）后才写。
 * 没写就下次启动重试 —— 迁移流水用的是确定性 id，重复搬不会重复入账。
 */
const MIGRATED_KEY = 'sekainook_garden_migrated';
/**
 * 离线队列单独存一个键（数组，一条一个操作）：断网时打的分先压在这里，
 * 联网后按顺序补发。同一个操作重试复用同一个 id，服务端靠主键做幂等。
 */
const PENDING_KEY = 'sekainook_garden_pending';
/** 迁移流水的确定性 id（重试复用同一个 → 服务端靠主键 INSERT OR IGNORE 幂等） */
const MIGRATION_LEGACY_ID = 'mig_legacy';
const MIGRATION_SHOP_ID_PREFIX = 'mig_shop_';

/** 离线队列的补发节奏 */
const FLUSH_INTERVAL_MS = 30_000;

/** 与「今日任务」联动的任务 id：背诗 / 语文练习完成时同步点亮 */
const POEM_TASK_ID = 'poem';
const CHINESE_TASK_ID = 'chinese';

/** 商城兑换结果 */
export type ShopBuyResult = 'ok' | 'owned' | 'insufficient' | 'unknown';

/** 已经乐观生效、但还没成功写进账本的一次花园操作 */
export interface PendingGardenOp {
  /** 客户端生成的幂等 id：重试必须复用同一个（服务端靠主键去重） */
  id: string;
  /** 账本 task_id：'garden:xxx' / 'garden_shop:xxx' / 'garden_legacy' */
  taskId: string;
  kind: 'earn' | 'spend';
  /** 正数加分、负数扣分；乐观值就是它 */
  amount: number;
  /** 购买类操作的商品 id（被服务端拒绝时用来收回物品） */
  itemId?: string;
  at: number;
}

interface GardenStore {
  /**
   * 花园阳光余额（消费方直接用这个，页面不用改）：
   * = 账本派生值（全量余额接口 → 本地缓存流水 → 上次算出的值）+ 本地未同步增量（pendingDelta）。
   */
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
  /** 已拥有的商城物品 id（本地清单 ∪ 账本里买过的） */
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

  /** 全量余额接口拿到的阳光（null = 这次会话还没拿到过）；权威值，不含未同步增量 */
  summarySun: number | null;
  /** 本地缓存的花园流水：全量接口不通时的回退，也用来认「账本里买过的商品」 */
  cachedRecords: LedgerRecord[];
  /** 上次算出的权威余额（落 localStorage）：离线冷启动的最后一道兜底 */
  cachedSun: number;
  /** 还没成功写进账本的乐观操作（离线队列，先到先发） */
  pending: PendingGardenOp[];
  /** pending 的金额之和：displaySun = 权威余额 + pendingDelta */
  pendingDelta: number;

  /** 初始化（从 localStorage 恢复或使用默认；顺带补发队列、迁移老数据、拉一次权威余额） */
  init: () => void;
  /** 完成任务：增加阳光积分，更新完成状态，并把这一笔写进云端账本 */
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
  /** 补发离线队列：成功出队、被拒出队并回滚、网络失败留着下次 */
  flushPending: () => Promise<void>;
  /** 拉一次权威余额与账本流水（失败时保留上一次的值） */
  refreshLedger: () => Promise<void>;
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
  | 'cachedSun'
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

/** 安全读取可能为负数的金额（0 要保留，所以不能用 toSafeCount） */
function toSafeAmount(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? Math.round(value) : 0;
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

/**
 * 安全读取离线队列（兼容旧 state / 脏数据）。
 * 字段不全或金额不是数字的一律丢掉：宁可少发一笔，也别拿坏数据去记账。
 */
function toSafePendingOps(value: unknown): PendingGardenOp[] {
  if (!Array.isArray(value)) return [];
  const ops: PendingGardenOp[] = [];
  const seen = new Set<string>();
  for (const item of value) {
    if (!item || typeof item !== 'object') continue;
    const op = item as Partial<PendingGardenOp>;
    if (typeof op.id !== 'string' || !op.id || seen.has(op.id)) continue;
    if (typeof op.taskId !== 'string' || !op.taskId) continue;
    if (op.kind !== 'earn' && op.kind !== 'spend') continue;
    if (typeof op.amount !== 'number' || !Number.isFinite(op.amount)) continue;
    seen.add(op.id);
    ops.push({
      id: op.id,
      taskId: op.taskId,
      kind: op.kind,
      amount: Math.round(op.amount),
      ...(typeof op.itemId === 'string' && op.itemId ? { itemId: op.itemId } : {}),
      at: typeof op.at === 'number' && Number.isFinite(op.at) ? op.at : 0,
    });
  }
  return ops;
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
    cachedSun: state.cachedSun,
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

/** 保存状态到 localStorage（写入失败不能影响内存里的账） */
function saveState(state: PersistedGarden): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  } catch {
    // 隐私模式 / 配额满：这一份存不下就存不下，内存里的账照常
  }
}

/** 老数据迁移标志：读过就不再搬（标志位本身丢了也不要紧，迁移 id 是确定性的） */
function readMigratedFlag(): boolean {
  try {
    return localStorage.getItem(MIGRATED_KEY) !== null;
  } catch {
    return false;
  }
}

function writeMigratedFlag(): void {
  try {
    localStorage.setItem(MIGRATED_KEY, '1');
  } catch {
    // 写不进去也不影响这次的账
  }
}

/** 读取离线队列（坏数据一律丢掉，宁可少发一笔也别拿它去记账） */
function loadPending(): PendingGardenOp[] {
  try {
    const raw = localStorage.getItem(PENDING_KEY);
    return raw ? toSafePendingOps(JSON.parse(raw)) : [];
  } catch {
    return [];
  }
}

/** 写离线队列（写入失败不能影响内存里的账） */
function savePending(ops: PendingGardenOp[]): void {
  try {
    localStorage.setItem(PENDING_KEY, JSON.stringify(ops));
  } catch {
    // 存不下就存不下：内存里的队列还在，本次会话照样补发
  }
}

/**
 * 权威阳光余额（不含未同步增量）的三段回退：
 * ① 全量余额接口给出的值 → ② 本地缓存的花园流水算出来的值 → ③ 上次算出来并存下的值。
 */
export function resolveSunBase(input: {
  summarySun: number | null;
  cachedRecords: LedgerRecord[];
  cachedSun: number;
}): number {
  const { summarySun, cachedRecords, cachedSun } = input;
  if (typeof summarySun === 'number' && Number.isFinite(summarySun)) return summarySun;
  if (cachedRecords.length > 0) return calcGardenBalance(cachedRecords);
  return Number.isFinite(cachedSun) ? cachedSun : 0;
}

/** 造一笔加分操作（id 由客户端生成；同一次操作重试复用同一个 id） */
function earnOp(taskId: string, amount: number): PendingGardenOp {
  return { id: createRequestId(), taskId, kind: 'earn', amount, at: Date.now() };
}

/** 造一笔购买操作（金额为负；itemId 用于被服务端拒绝时收回物品） */
function spendOp(taskId: string, itemId: string, cost: number): PendingGardenOp {
  return { id: createRequestId(), taskId, kind: 'spend', amount: -cost, itemId, at: Date.now() };
}

/** 压进离线队列（同一个 id 已经在队列里就不重复压） */
function pushOp(pending: PendingGardenOp[], op: PendingGardenOp): PendingGardenOp[] {
  return pending.some((item) => item.id === op.id) ? pending : [...pending, op];
}

/** 这条队列操作是不是老数据迁移的一部分 */
function isMigrationOp(op: PendingGardenOp): boolean {
  return op.id === MIGRATION_LEGACY_ID || op.id.startsWith(MIGRATION_SHOP_ID_PREFIX);
}

/**
 * 老数据的迁移流水：一条 garden_legacy = 老余额 + 已购物品的钱（这样随后补发的购买记录
 * 扣完之后，派生余额正好等于老余额），再给每件已拥有的物品补一条购买记录。
 * id 全部是确定性的：中途失败下次启动重发同一批 id，服务端不会重复入账。
 */
function buildMigrationOps(legacyBalance: number, ownedItems: string[]): PendingGardenOp[] {
  const at = Date.now();
  const ops: PendingGardenOp[] = [];
  const ownedCost = ownedItems.reduce(
    (sum, id) => sum + (GARDEN_SHOP_ITEMS.find((item) => item.id === id)?.cost ?? 0),
    0
  );
  // 服务端会把 garden_legacy 夹到 [0, GARDEN_LEGACY_MAX]：客户端先夹一次，两边算出来的数一致
  const legacyAmount = Math.min(Math.max(Math.round(legacyBalance) + ownedCost, 0), GARDEN_LEGACY_MAX);
  if (legacyAmount > 0) {
    ops.push({
      id: MIGRATION_LEGACY_ID,
      taskId: GARDEN_LEGACY_TASK_ID,
      kind: 'earn',
      amount: legacyAmount,
      at,
    });
  }
  for (const itemId of ownedItems) {
    const item = GARDEN_SHOP_ITEMS.find((i) => i.id === itemId);
    // 不认识的物品（老版本删过的商品）搬不了，跳过
    if (!item) continue;
    ops.push({
      id: `${MIGRATION_SHOP_ID_PREFIX}${itemId}`,
      taskId: gardenShopTaskId(itemId),
      kind: 'spend',
      amount: -item.cost,
      itemId,
      at,
    });
  }
  return ops;
}

/** 已拥有的物品 = 本地清单 ∪ 账本里出现过的 garden_shop:*（换手机后买到的东西还在） */
function mergeOwnedItems(local: string[], records: LedgerRecord[]): string[] {
  const owned = new Set(local);
  for (const record of records) {
    if (record.status === 'rejected') continue;
    const itemId = gardenShopItemId(record.task_id);
    if (itemId && GARDEN_SHOP_ITEMS.some((item) => item.id === itemId)) owned.add(itemId);
  }
  return Array.from(owned);
}

/**
 * 提交一次状态变更。余额相关的派生字段统一在这里重算，调用方不用自己算 balance：
 *   displaySun = 权威余额（summarySun / 本地流水 / 缓存）+ 未同步增量（pendingDelta）
 */
function commit(patch: Partial<GardenStore>): void {
  useGardenStore.setState((state) => {
    const summarySun = patch.summarySun !== undefined ? patch.summarySun : state.summarySun;
    const cachedRecords = patch.cachedRecords ?? state.cachedRecords;
    const pending = patch.pending ?? state.pending;
    const pendingDelta = pending.reduce((sum, op) => sum + op.amount, 0);
    const cachedSun = resolveSunBase({
      summarySun,
      cachedRecords,
      cachedSun: patch.cachedSun ?? state.cachedSun,
    });
    return { ...patch, pending, pendingDelta, cachedSun, balance: cachedSun + pendingDelta };
  });
  const state = useGardenStore.getState();
  saveState(toPersisted(state));
  // 离线队列单独存一个键：只有它变了才写，免得每次打卡都整车重写一遍
  if (patch.pending) savePending(state.pending);
}

/** 同一时刻只允许一次补发（init / online / 定时器可能同时触发） */
let flushing = false;

/**
 * 一笔队列操作的最终结果：
 * - 'written'：已经进账本了（含 duplicate）。把这一笔从「未同步增量」挪进「权威余额」，
 *   显示值在出队那一刻不跳变（紧接着的全量刷新会给出真正的权威值）。
 * - 'rejected'：服务端明确拒绝（日限用完 / 金额非法）。出队并回滚乐观值：
 *   加分回滚为减掉那笔，购买回滚为退款 + 不再拥有。
 */
function settleOp(op: PendingGardenOp, outcome: 'written' | 'rejected'): void {
  const state = useGardenStore.getState();
  const patch: Partial<GardenStore> = {
    pending: state.pending.filter((item) => item.id !== op.id),
  };
  if (outcome === 'written') {
    patch.summarySun = resolveSunBase(state) + op.amount;
  } else if (op.kind === 'spend' && op.itemId) {
    patch.ownedItems = state.ownedItems.filter((id) => id !== op.itemId);
  }
  commit(patch);
}

/** 迁移流水全部有了结果（入账 / duplicate / 被拒）才落标志位，中途失败下次启动再来 */
function markMigratedIfSettled(): void {
  if (readMigratedFlag()) return;
  if (useGardenStore.getState().pending.some(isMigrationOp)) return;
  writeMigratedFlag();
}

/**
 * 补发离线队列：成功的出队、被服务端拒绝的出队并回滚乐观值，
 * 网络 / 5xx 失败的原样留在队列里等下次。只要有一笔有结果就顺手刷一次全量余额。
 */
async function flushPending(): Promise<void> {
  if (flushing) return;
  flushing = true;
  let settled = 0;
  let migrationRejected = false;
  try {
    for (;;) {
      const op = useGardenStore.getState().pending[0];
      if (!op) break;
      try {
        // 名字 / 类型 / 金额都交给服务端规则，客户端只给 task_id 和幂等 id
        await postLedgerRecord(op.taskId, {
          requestId: op.id,
          amount: op.amount,
          name: op.taskId,
          type: op.kind === 'spend' ? 'spending' : 'earning',
        });
        settleOp(op, 'written');
        settled += 1;
      } catch (error) {
        // 暂时不通（fetch 失败 / 5xx / 429）：留在队列里，下次再试
        if (!isRejectedWriteError(error)) break;
        if (isMigrationOp(op)) migrationRejected = true;
        settleOp(op, 'rejected');
        settled += 1;
      }
    }
    // 有迁移流水被拒就宁可不落标志位：老余额可能是撞上「一天只能迁一次」的限制，明天再来
    if (!migrationRejected) markMigratedIfSettled();
  } finally {
    flushing = false;
  }
  if (settled > 0) await refreshLedger();
}

/** 拉一次权威数据：全量余额（sun）+ 最近流水（账本里买过的商品 = 换手机后仍然拥有） */
async function refreshLedger(): Promise<void> {
  const state = useGardenStore.getState();
  const [summary, records] = await Promise.allSettled([fetchLedgerSummary(), fetchLedgerRecords()]);
  // 两个都没通：保留上一次的值（宁可显示旧数字，也不要因为一次失败把阳光清零）
  if (summary.status === 'rejected' && records.status === 'rejected') return;

  const patch: Partial<GardenStore> = {};
  // 已经拿到过全量值时，records 那 200 条窗口算出来的数只用来兜底认商品，不用来改余额
  if (summary.status === 'fulfilled') patch.summarySun = summary.value.sun;
  if (records.status === 'fulfilled') {
    patch.cachedRecords = records.value.filter((record) => isGardenTaskId(record.task_id));
    patch.ownedItems = mergeOwnedItems(state.ownedItems, records.value);
  }
  commit(patch);
}

/** 联网 / 定时补发：只挂一次 */
let syncLoopReady = false;
function ensureSyncLoop(): void {
  if (syncLoopReady) return;
  syncLoopReady = true;
  if (typeof window !== 'undefined') {
    window.addEventListener('online', () => {
      void flushPending();
    });
  }
  if (typeof setInterval === 'function') {
    setInterval(() => {
      // 页面在后台时不打扰：回到前台时 visibilitychange / focus 会补一次
      if (typeof document !== 'undefined' && document.hidden) return;
      void flushPending();
    }, FLUSH_INTERVAL_MS);
  }
}

export const useGardenStore = create<GardenStore>((_set, get) => ({
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

  summarySun: null,
  cachedRecords: [],
  cachedSun: 0,
  pending: [],
  pendingDelta: 0,

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

    const ownedItems = toSafeStringArray(saved.ownedItems);
    const migrated = readMigratedFlag();
    // 老版本的花园阳光只存在这台手机的 localStorage 里：标志位还没写、且确实有东西要搬时补一组迁移流水
    const needsMigration = !migrated && (balance > 0 || ownedItems.length > 0);
    // 权威余额的兜底缓存：要迁移的老用户从 0 起算（老余额由迁移流水搬进来），
    // 否则用上次算出的权威值（再老的存档没有它时退回老 balance，至少不会显示 0）
    const cachedSun = needsMigration
      ? 0
      : typeof saved.cachedSun === 'number'
        ? toSafeAmount(saved.cachedSun)
        : toSafeAmount(saved.balance);
    let pending = loadPending();
    for (const op of needsMigration ? buildMigrationOps(balance, ownedItems) : []) {
      pending = pushOp(pending, op);
    }

    commit({
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
      ownedItems,
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
      cachedSun,
      pending,
      // 已经拿到过的权威值 / 本地流水不清零（重复 init 或回到页面时保留）
      summarySun: get().summarySun,
      cachedRecords: get().cachedRecords,
    });
    // 没有东西要搬：直接落标志位，之后不再检查
    if (!needsMigration) writeMigratedFlag();
    ensureSyncLoop();
    // 先把队列（含迁移）补发出去，再拉一次权威余额
    void flushPending();
    void refreshLedger();
  },

  completeTask: (taskId) => {
    const state = get();
    const task = state.tasks.find((t) => t.id === taskId);
    if (!task || task.done) return;

    const today = toDateKey(new Date());
    const stats = nextCompletionStats(state, task.reward, today, true);
    commit({
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
      // 这一笔同时进云端账本（离线时先压进队列，联网后补发）
      pending: pushOp(state.pending, earnOp(gardenTaskId(task.id), task.reward)),
    });
    void flushPending();
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
    commit({
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
      // 背诗一律记 'garden:poem'（一天可多首，服务端不设日限）
      pending: pushOp(state.pending, earnOp(gardenTaskId(POEM_TASK_ID), poem.reward)),
    });
    void flushPending();
    return true;
  },

  completeChineseStep: (practiceId) => {
    const state = get();
    const practice = GARDEN_CHINESE_PRACTICES.find((p) => p.id === practiceId);
    if (!practice) return false;

    const today = toDateKey(new Date());
    const steps = state.chineseDate === today ? state.chineseSteps : {};
    const done = steps[practiceId] ?? 0;
    // 每天每项练习的打卡次数上限（本地先挡一道，服务端的日限是最后一道）
    if (done >= practice.timesPerDay) return false;

    const chineseTaskDone = state.tasks.find((t) => t.id === CHINESE_TASK_ID)?.done ?? false;
    const stats = nextCompletionStats(state, practice.reward, today, !chineseTaskDone);
    commit({
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
      // 记 'garden:' + 练习 id（read_aloud / new_words / write_words），日限由服务端兜
      pending: pushOp(state.pending, earnOp(gardenTaskId(practiceId), practice.reward)),
    });
    void flushPending();
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
    // 浇水本身不发阳光（服务端没有对应规则），所以不进队列
    commit({
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
    });
    return true;
  },

  buyItem: (itemId) => {
    const state = get();
    const item = GARDEN_SHOP_ITEMS.find((i) => i.id === itemId);
    if (!item) return 'unknown';
    if (state.ownedItems.includes(itemId)) return 'owned';
    if (state.balance < item.cost) return 'insufficient';

    commit({
      ownedItems: [...state.ownedItems, itemId],
      // 价格由服务端规则决定（这里只是先乐观扣一笔）
      pending: pushOp(state.pending, spendOp(gardenShopTaskId(itemId), itemId, item.cost)),
    });
    void flushPending();
    return 'ok';
  },

  equipItem: (itemId) => {
    const state = get();
    const item = GARDEN_SHOP_ITEMS.find((i) => i.id === itemId);
    if (!item) return 'unknown';
    // 没买过就不让用：商城页只给已拥有的物品显示「戴上 / 挂上」
    if (!state.ownedItems.includes(itemId)) return 'owned';

    if (item.category === 'avatar') {
      // 头像框一次只戴一个：换上新的就把旧的换下来
      commit({ equippedAvatar: itemId });
    } else if (item.category === 'title') {
      // 称号同理，一次只挂一个
      commit({ equippedTitle: itemId });
    } else {
      // 装饰可以同时挂好几件：先去掉可能重复的同一件，再挂到最后
      const rest = state.equippedDecor.filter((id) => id !== itemId);
      // 挂满 GARDEN_MAX_DECOR 件时，替换掉最早挂上的那件（数组头部）
      const kept =
        rest.length >= GARDEN_MAX_DECOR ? rest.slice(rest.length - (GARDEN_MAX_DECOR - 1)) : rest;
      commit({ equippedDecor: [...kept, itemId] });
    }
    return 'ok';
  },

  unequipItem: (itemId) => {
    const state = get();
    const item = GARDEN_SHOP_ITEMS.find((i) => i.id === itemId);
    // 不认识的物品直接忽略，页面不会因此崩
    if (!item) return;

    if (item.category === 'avatar') {
      if (state.equippedAvatar === itemId) commit({ equippedAvatar: null });
    } else if (item.category === 'title') {
      if (state.equippedTitle === itemId) commit({ equippedTitle: null });
    } else {
      commit({ equippedDecor: state.equippedDecor.filter((id) => id !== itemId) });
    }
  },

  flushPending,

  refreshLedger,
}));
