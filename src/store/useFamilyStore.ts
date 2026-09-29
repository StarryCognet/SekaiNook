import { create } from 'zustand';
import {
  fetchLedgerRecords,
  fetchPendingRequests,
  approveRequest,
  rejectRequest,
  deleteLedgerRecord,
  calcApprovedBalance,
} from '../api/familyLedger';
import type { LedgerRecord } from '../types/family';

/** 当前身份：家长（可审批）/ 小孩（打卡需审批） */
export type FamilyRole = 'parent' | 'child';

const ROLE_KEY = 'sekainook_role';
const PIN_KEY = 'sekainook_parent_pin';
/** 出厂家长口令（家长可在设置页修改） */
const DEFAULT_PARENT_PIN = '1234';

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
  balance: number;
  records: LedgerRecord[];
  /** 待审批申请列表 */
  pendingRecords: LedgerRecord[];
  /** 待审批申请数量 */
  pendingCount: number;
  loading: boolean;
  /** 切换身份（持久化到 localStorage） */
  setRole: (role: FamilyRole) => void;
  /** 读取家长口令（未设置返回出厂口令） */
  getParentPin: () => string;
  /** 更新家长口令（家长在设置页修改） */
  setParentPin: (pin: string) => void;
  /** 拉取流水与余额（单一数据源：余额由已审批记录计算）与待审批数量 */
  loadLedger: () => Promise<void>;
  /** 仅刷新待审批数量（轮询用） */
  refreshPending: () => Promise<void>;
  /** 审批通过 */
  approve: (id: string) => Promise<void>;
  /** 审批驳回 */
  reject: (id: string) => Promise<void>;
  /** 删除一条流水（仅家长），后端会一并删除关联图片 */
  removeRecord: (id: string) => Promise<void>;
}

/** 家庭积分银行全局状态 */
export const useFamilyStore = create<FamilyState>((set, get) => ({
  role: loadRole(),
  balance: 0,
  records: [],
  pendingRecords: [],
  pendingCount: 0,
  loading: false,

  setRole: (role) => {
    localStorage.setItem(ROLE_KEY, role);
    set({ role });
  },

  getParentPin: () => {
    const raw = localStorage.getItem(PIN_KEY);
    return raw && raw.length > 0 ? raw : DEFAULT_PARENT_PIN;
  },

  setParentPin: (pin) => {
    localStorage.setItem(PIN_KEY, pin);
  },

  loadLedger: async () => {
    set({ loading: true });
    try {
      const [records, pending] = await Promise.all([
        fetchLedgerRecords(),
        fetchPendingRequests(),
      ]);
      set({
        records,
        pendingRecords: pending,
        pendingCount: pending.length,
        balance: calcApprovedBalance(records),
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

  reject: async (id) => {
    await rejectRequest(id);
    await get().loadLedger();
  },

  removeRecord: async (id) => {
    await deleteLedgerRecord(id);
    await get().loadLedger();
  },
}));
