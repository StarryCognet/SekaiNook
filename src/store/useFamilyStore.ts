import { create } from 'zustand';
import {
  fetchLedgerRecords,
  fetchPendingRequests,
  approveRequest,
  rejectRequest,
  calcApprovedBalance,
} from '../api/familyLedger';
import type { LedgerRecord } from '../types/family';

/** 当前身份：家长（可审批）/ 小孩（打卡需审批） */
export type FamilyRole = 'parent' | 'child';

const ROLE_KEY = 'sekainook_role';
const PIN_KEY = 'sekainook_parent_pin';
/** 出厂家长口令（家长可在设置页修改） */
const DEFAULT_PARENT_PIN = '1234';

/** 从 localStorage 恢复身份（缺省为家长，保持现有行为不变） */
function loadRole(): FamilyRole {
  const raw = localStorage.getItem(ROLE_KEY);
  return raw === 'child' ? 'child' : 'parent';
}

interface FamilyState {
  /** 当前身份 */
  role: FamilyRole;
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
}));
