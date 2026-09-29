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
const MEMBERS_KEY = 'sekainook_members';
const ACTIVE_MEMBER_KEY = 'sekainook_active_member';
/** 出厂家长口令（家长可在设置页修改） */
const DEFAULT_PARENT_PIN = '1234';
/** 成员数量上限（够用即可，避免把选择器撑爆） */
const MAX_MEMBERS = 6;

/**
 * 从 localStorage 恢复身份。
 * 未设置时返回 null（首次打开的设备），交给 RoleGate 让用户选身份 ——
 * 不能缺省为家长：否则妹妹的手机第一次打开就是家长模式，可以自己审批自己的申请。
 */
function loadRole(): FamilyRole | null {
  const raw = localStorage.getItem(ROLE_KEY);
  return raw === 'child' || raw === 'parent' ? raw : null;
}

/**
 * 家庭成员名单（多孩子场景，可选）。
 * 默认空数组：单孩子家庭不配置成员，界面上完全不出现这个概念，行为与旧版一致。
 */
function loadMembers(): string[] {
  try {
    const raw = localStorage.getItem(MEMBERS_KEY);
    if (!raw) return [];
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((m): m is string => typeof m === 'string' && m.trim().length > 0);
  } catch {
    return [];
  }
}

/** 恢复上次选中的成员（必须仍在名单里；null 表示看全部/未指定） */
function loadActiveMember(members: string[]): string | null {
  const raw = localStorage.getItem(ACTIVE_MEMBER_KEY);
  return raw && members.includes(raw) ? raw : null;
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
  /** 家庭成员名单（空数组 = 未启用多成员） */
  members: string[];
  /** 当前选中的成员（null = 全部/未指定） */
  activeMember: string | null;
  /** 切换身份（持久化到 localStorage） */
  setRole: (role: FamilyRole) => void;
  /** 读取家长口令（未设置返回出厂口令） */
  getParentPin: () => string;
  /** 更新家长口令（家长在设置页修改） */
  setParentPin: (pin: string) => void;
  /** 新增家庭成员（去空格、重名或超上限则忽略），并自动选中它 */
  addMember: (name: string) => void;
  /** 移除家庭成员（若正被选中则回到「全部」） */
  removeMember: (name: string) => void;
  /** 选择/取消选中成员 */
  setActiveMember: (name: string | null) => void;
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
  members: loadMembers(),
  activeMember: loadActiveMember(loadMembers()),

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

  addMember: (name) => {
    const trimmed = name.trim().slice(0, 20);
    const { members } = get();
    if (!trimmed || members.includes(trimmed) || members.length >= MAX_MEMBERS) return;
    const next = [...members, trimmed];
    localStorage.setItem(MEMBERS_KEY, JSON.stringify(next));
    localStorage.setItem(ACTIVE_MEMBER_KEY, trimmed);
    set({ members: next, activeMember: trimmed });
  },

  removeMember: (name) => {
    const next = get().members.filter((m) => m !== name);
    localStorage.setItem(MEMBERS_KEY, JSON.stringify(next));
    const activeMember = get().activeMember === name ? null : get().activeMember;
    if (activeMember) {
      localStorage.setItem(ACTIVE_MEMBER_KEY, activeMember);
    } else {
      localStorage.removeItem(ACTIVE_MEMBER_KEY);
    }
    set({ members: next, activeMember });
  },

  setActiveMember: (name) => {
    if (name) {
      localStorage.setItem(ACTIVE_MEMBER_KEY, name);
    } else {
      localStorage.removeItem(ACTIVE_MEMBER_KEY);
    }
    set({ activeMember: name });
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
