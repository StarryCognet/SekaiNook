import { create } from 'zustand';
import {
  fetchLedgerRecords,
  fetchLedgerSummary,
  fetchPendingRequests,
  approveRequest,
  rejectRequest,
  deleteLedgerRecord,
  calcApprovedBalance,
  calcGardenBalance,
  isGardenTaskId,
} from '../api/familyLedger';
import type { LedgerRecord } from '../types/family';

/** 当前身份：家长（可审批）/ 小孩（打卡需审批） */
export type FamilyRole = 'parent' | 'child';

const ROLE_KEY = 'sekainook_role';
/** 新键：只放口令摘要（安全上下文不可用时降级为带前缀的明文），不再放裸明文 */
const PIN_KEY = 'sekainook_parent_pin_hash';
/** 老键：历史版本在这里存的是明文口令，首次读到就迁移到新键并删掉 */
const LEGACY_PIN_KEY = 'sekainook_parent_pin';
/** 摘要的固定 salt 前缀，避免有人拿现成的 SHA-256 彩虹表直接反查 4 位数字口令 */
const PIN_SALT = 'sekainook-pin:';
/** 存储值前缀：一眼看清这一条是摘要还是降级明文（也用于容错解析） */
const HASH_PREFIX = 'sha256:';
const PLAIN_PREFIX = 'plain:';
/** 出厂家长口令（家长可在设置页修改） */
const DEFAULT_PARENT_PIN = '1234';

/** 允许连续失败的次数，超过就锁定 */
const MAX_FREE_ATTEMPTS = 5;
/** 锁定时长：第 5 次失败锁 60 秒，之后每多失败一次翻倍，上限 10 分钟 */
const BASE_LOCK_MS = 60_000;
const MAX_LOCK_MS = 10 * 60_000;

/** 失败计数与锁定截止时刻 —— 都落 localStorage，刷新/重开页面绕不过去 */
const PIN_FAIL_KEY = 'sekainook_parent_pin_fails';
const PIN_LOCK_KEY = 'sekainook_parent_pin_lock_until';

/**
 * crypto.subtle 只在安全上下文（https / localhost）里存在。
 * 内网用 http 打开时它是 undefined —— 那种情况下降级回明文存储（见 writePin）。
 */
function subtleCrypto(): SubtleCrypto | null {
  const maybe = (globalThis as { crypto?: { subtle?: SubtleCrypto } }).crypto;
  return maybe?.subtle ?? null;
}

/** 口令 → SHA-256 十六进制摘要（PIN_SALT 作为固定 salt 前缀） */
async function hashPin(pin: string): Promise<string> {
  const subtle = subtleCrypto();
  if (!subtle) throw new Error('当前环境不支持口令加密');
  const bytes = new TextEncoder().encode(PIN_SALT + pin);
  const digest = await subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * 写入新口令。
 * 安全上下文：存 `sha256:<hex>`，localStorage 里再也看不到明文。
 * 非安全上下文（内网 http，没有 crypto.subtle）：只能降级成 `plain:<明文>` ——
 *   宁可退回原来的明文行为，也不能让家长写不进去、校验不了，被关在自己家门外。
 */
async function writePin(pin: string): Promise<void> {
  if (subtleCrypto()) {
    localStorage.setItem(PIN_KEY, HASH_PREFIX + (await hashPin(pin)));
    return;
  }
  console.warn('[SekaiNook] 当前非安全上下文，家长口令降级为明文存储');
  localStorage.setItem(PIN_KEY, PLAIN_PREFIX + pin);
}

type StoredPin = { mode: 'hash' | 'plain'; value: string };

/**
 * 同步读当前口令记录。这里只给本模块内部用 ——
 * 不再对外暴露 getParentPin 这类能拿到"可比对字符串"的接口，避免有人再拿明文比。
 */
function readStoredPin(): StoredPin | null {
  const raw = localStorage.getItem(PIN_KEY);
  if (raw) {
    if (raw.startsWith(HASH_PREFIX)) {
      return { mode: 'hash', value: raw.slice(HASH_PREFIX.length) };
    }
    if (raw.startsWith(PLAIN_PREFIX)) {
      return { mode: 'plain', value: raw.slice(PLAIN_PREFIX.length) };
    }
    return { mode: 'plain', value: raw }; // 容错：没有前缀的旧格式，按明文比
  }
  const legacy = localStorage.getItem(LEGACY_PIN_KEY);
  return legacy ? { mode: 'plain', value: legacy } : null;
}

/**
 * 首次读取时顺手迁移老键：明文 → 新键（能算摘要就算摘要，算不了就把明文搬到新键），
 * 成功后删掉老键。迁移是幂等的；写入抛错时不删老键，绝不会因此把人锁在门外。
 */
async function migrateLegacyPin(): Promise<void> {
  const legacy = localStorage.getItem(LEGACY_PIN_KEY);
  if (legacy === null) return;
  await writePin(legacy);
  localStorage.removeItem(LEGACY_PIN_KEY);
}

function readFails(): number {
  const raw = Number(localStorage.getItem(PIN_FAIL_KEY));
  return Number.isFinite(raw) && raw > 0 ? Math.floor(raw) : 0;
}

function writeFails(fails: number): void {
  if (fails > 0) localStorage.setItem(PIN_FAIL_KEY, String(fails));
  else localStorage.removeItem(PIN_FAIL_KEY);
}

/** 距离解锁还剩多少毫秒（0 = 未锁定）。纯同步读 */
function lockRemainingMs(): number {
  const until = Number(localStorage.getItem(PIN_LOCK_KEY));
  if (!Number.isFinite(until)) return 0;
  return Math.max(0, until - Date.now());
}

/** 还剩几次机会（给 UI 显示「还可以试 N 次」） */
function attemptsLeft(): number {
  return Math.max(0, MAX_FREE_ATTEMPTS - readFails());
}

/** 校验成功 / 改口令成功时清零失败计数与锁定 */
function clearPinGuards(): void {
  localStorage.removeItem(PIN_FAIL_KEY);
  localStorage.removeItem(PIN_LOCK_KEY);
}

/** 记一次失败：从第 MAX_FREE_ATTEMPTS 次起锁定，往后每多失败一次时长翻倍（上限 10 分钟） */
function registerPinFailure(): void {
  const fails = readFails() + 1;
  writeFails(fails);
  if (fails < MAX_FREE_ATTEMPTS) return;
  const lockMs = Math.min(BASE_LOCK_MS * 2 ** (fails - MAX_FREE_ATTEMPTS), MAX_LOCK_MS);
  localStorage.setItem(PIN_LOCK_KEY, String(Date.now() + lockMs));
}

/**
 * 校验家长口令：异步比对 + 失败锁定。
 * - 锁定期内直接 false（不校验、不计失败，也不透露任何关于正确口令的信息）；
 * - 成功清零失败计数；
 * - 失败累计到阈值就锁定，锁定时长逐次翻倍。
 */
async function verifyParentPin(pin: string): Promise<boolean> {
  // 锁定期内连正确口令也返回 false —— 这是"锁"的意义所在
  if (lockRemainingMs() > 0) return false;

  await migrateLegacyPin();
  const stored = readStoredPin();

  // 还没设过口令：出厂口令生效（这条路径本地不存任何东西）
  if (!stored) {
    if (pin !== DEFAULT_PARENT_PIN) {
      registerPinFailure();
      return false;
    }
    clearPinGuards();
    return true;
  }

  if (stored.mode === 'hash') {
    if (!subtleCrypto()) {
      // 摘要是在安全上下文里写的，当前环境算不出摘要 → 谁也没法校验。
      // 这里拒绝但【不】计失败：否则用 http 打开一次就把家长自己锁住了。
      console.warn(
        '[SekaiNook] 当前非安全上下文，无法校验已保存的家长口令摘要；请用 https 或 localhost 打开'
      );
      return false;
    }
    if ((await hashPin(pin)) === stored.value) {
      clearPinGuards();
      return true;
    }
    registerPinFailure();
    return false;
  }

  if (pin === stored.value) {
    clearPinGuards();
    return true;
  }
  registerPinFailure();
  return false;
}

/**
 * 从 localStorage 恢复身份。
 * 未设置时返回 null（首次打开的设备），交给 RoleGate 让用户选身份 ——
 * 不能缺省为家长：否则妹妹的手机第一次打开就是家长模式，可以自己审批自己的申请。
 */
function loadRole(): FamilyRole | null {
  const raw = localStorage.getItem(ROLE_KEY);
  return raw === 'child' || raw === 'parent' ? raw : null;
}

interface FamilyState {
  /** 当前身份（null = 尚未选择，由 RoleGate 引导） */
  role: FamilyRole | null;
  /** 家庭已入账积分（全量余额接口，拿不到时退回已审批记录求和；不含花园阳光） */
  balance: number;
  /** 家庭流水（**不含花园阳光**）：家长账本页看到的就是这些 */
  records: LedgerRecord[];
  /** 花园阳光流水（同一个账本、另一个视图，供花园记录页用） */
  gardenRecords: LedgerRecord[];
  /** 花园阳光余额（全量余额接口，拿不到时退回 gardenRecords 求和） */
  sunBalance: number;
  /** 待审批申请列表 */
  pendingRecords: LedgerRecord[];
  /** 待审批申请数量 */
  pendingCount: number;
  loading: boolean;
  /** 切换身份（持久化到 localStorage） */
  setRole: (role: FamilyRole) => void;
  /** 校验家长口令（异步比对摘要 + 失败锁定）；锁定期内即使输入正确也返回 false */
  verifyParentPin: (pin: string) => Promise<boolean>;
  /** 更新家长口令（安全上下文只存 SHA-256 摘要，不可用时降级明文） */
  setParentPin: (pin: string) => Promise<void>;
  /** 距离解锁还剩多少毫秒（0 = 未锁定）。纯同步读，供 UI 显示倒计时 */
  pinLockRemainingMs: () => number;
  /** 还能试几次（锁定中为 0），供 UI 显示「还可以试 N 次」 */
  pinAttemptsLeft: () => number;
  /** 是否设置过自己的家长口令（只表明"设过"，不比对也不暴露口令本身） */
  hasCustomParentPin: () => boolean;
  /** 拉取流水与余额（单一数据源：余额由已审批记录计算）与待审批数量 */
  loadLedger: () => Promise<void>;
  /** 仅刷新待审批数量（轮询用） */
  refreshPending: () => Promise<void>;
  /** 审批通过 */
  approve: (id: string) => Promise<void>;
  /** 批量审批通过（逐条提交，最后统一刷新一次） */
  approveMany: (ids: string[]) => Promise<void>;
  /** 审批驳回（reason 会原样带给孩子看） */
  reject: (id: string, reason?: string) => Promise<void>;
  /** 删除一条流水（仅家长），后端会一并删除关联图片 */
  removeRecord: (id: string) => Promise<void>;
}

/** 家庭积分银行全局状态 */
export const useFamilyStore = create<FamilyState>((set, get) => ({
  role: loadRole(),
  balance: 0,
  records: [],
  gardenRecords: [],
  sunBalance: 0,
  pendingRecords: [],
  pendingCount: 0,
  loading: false,

  setRole: (role) => {
    localStorage.setItem(ROLE_KEY, role);
    set({ role });
  },

  verifyParentPin,

  setParentPin: async (pin) => {
    await writePin(pin);
    // 改完口令顺手解锁：家长已经站在家长模式里了，没必要再等倒计时
    clearPinGuards();
  },

  pinLockRemainingMs: () => lockRemainingMs(),

  pinAttemptsLeft: () => attemptsLeft(),

  hasCustomParentPin: () => readStoredPin() !== null,

  loadLedger: async () => {
    set({ loading: true });
    try {
      // 全量余额单独兜底：老部署还没有 /api/ledger/summary 时退回用流水算，
      // 但流水只有最近 200 条，所以能拿到 summary 就一定要用 summary（否则余额会越用越少）
      const [allRecords, pending, summary] = await Promise.all([
        fetchLedgerRecords(),
        fetchPendingRequests(),
        fetchLedgerSummary().catch(() => null),
      ]);
      // 同一个账本拆成两本：家长 / 家庭界面只看非花园流水，花园流水走 gardenRecords
      const records = allRecords.filter((record) => !isGardenTaskId(record.task_id));
      const gardenRecords = allRecords.filter((record) => isGardenTaskId(record.task_id));
      set({
        records,
        gardenRecords,
        pendingRecords: pending,
        pendingCount: pending.length,
        balance: summary ? summary.family : calcApprovedBalance(records),
        sunBalance: summary ? summary.sun : calcGardenBalance(gardenRecords),
        loading: false,
      });
    } catch (e) {
      set({ loading: false });
      throw e;
    }
  },

  refreshPending: async () => {
    const pending = await fetchPendingRequests();
    set({ pendingRecords: pending, pendingCount: pending.length });
  },

  approve: async (id) => {
    await approveRequest(id);
    await get().loadLedger();
  },

  approveMany: async (ids) => {
    // 一条失败不拖累其余：整批先跑完，再统一刷新一次账本
    const results = await Promise.allSettled(ids.map((id) => approveRequest(id)));
    await get().loadLedger();
    const failed = results.filter((r) => r.status === 'rejected').length;
    if (failed > 0) {
      throw new Error(`有 ${failed} 条没通过，请重试`);
    }
  },

  reject: async (id, reason) => {
    await rejectRequest(id, reason);
    await get().loadLedger();
  },

  removeRecord: async (id) => {
    await deleteLedgerRecord(id);
    await get().loadLedger();
  },
}));
