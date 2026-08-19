import { create } from 'zustand';
import { fetchLedgerRecords, getBalance } from '../api/familyLedger';
import type { LedgerRecord } from '../types/family';

interface FamilyState {
  balance: number;
  records: LedgerRecord[];
  loading: boolean;
  /** 拉取余额与流水 */
  loadLedger: () => Promise<void>;
  /** 刷新余额（打卡后调用） */
  refreshBalance: () => Promise<void>;
}

/** 家庭积分银行全局状态 */
export const useFamilyStore = create<FamilyState>((set) => ({
  balance: 0,
  records: [],
  loading: false,

  loadLedger: async () => {
    set({ loading: true });
    try {
      const [balance, records] = await Promise.all([getBalance(), fetchLedgerRecords()]);
      set({ balance, records, loading: false });
    } catch (e) {
      set({ loading: false });
      throw e;
    }
  },

  refreshBalance: async () => {
    const balance = await getBalance();
    set({ balance });
  },
}));