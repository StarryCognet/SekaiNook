/**
 * 家庭称呼（妈妈叫女儿、女儿叫妈妈）的全局状态。
 *
 * 权威数据在服务端（D1 settings 表），localStorage 只当缓存：
 * 打开 App 先用缓存渲染，再去服务端对一次，这样两个人换手机也能看到同一套称呼。
 */

import { create } from 'zustand';
import { fetchSettings, saveSettings } from '../api/settings';
import { DEFAULT_FAMILY_NAMES, displayName, type FamilyNames } from '../types/settings';

const CACHE_KEY = 'sekainook_family_names';

/** 读本地缓存（坏数据一律回默认值，不让设置问题拦住首页） */
function loadCache(): FamilyNames {
  try {
    const raw = localStorage.getItem(CACHE_KEY);
    if (!raw) return DEFAULT_FAMILY_NAMES;
    const parsed = JSON.parse(raw) as Partial<FamilyNames>;
    return {
      momCall: typeof parsed.momCall === 'string' && parsed.momCall ? parsed.momCall : DEFAULT_FAMILY_NAMES.momCall,
      momNickname: typeof parsed.momNickname === 'string' ? parsed.momNickname : '',
      kidCall: typeof parsed.kidCall === 'string' && parsed.kidCall ? parsed.kidCall : DEFAULT_FAMILY_NAMES.kidCall,
      kidNickname: typeof parsed.kidNickname === 'string' ? parsed.kidNickname : '',
    };
  } catch {
    return DEFAULT_FAMILY_NAMES;
  }
}

function saveCache(names: FamilyNames): void {
  try {
    localStorage.setItem(CACHE_KEY, JSON.stringify(names));
  } catch {
    // 隐私模式 / 存储满：拿不到缓存也不影响本次使用
  }
}

interface SettingsState {
  names: FamilyNames;
  loading: boolean;
  /** false = 服务端还没就绪（表没迁移 / 请求失败），当前用缓存或默认值 */
  ready: boolean;
  load: () => Promise<void>;
  save: (patch: Partial<FamilyNames>) => Promise<FamilyNames>;
}

export const useSettingsStore = create<SettingsState>((set, get) => ({
  names: loadCache(),
  loading: false,
  ready: false,

  /** 从服务端拉一次称呼；失败保留当前值（缓存/默认），不打扰用户 */
  load: async () => {
    if (get().loading) return;
    set({ loading: true });
    try {
      const { names, ready } = await fetchSettings();
      saveCache(names);
      set({ names, ready: ready !== false, loading: false });
    } catch {
      set({ loading: false, ready: false });
    }
  },

  /** 保存自己那一半称呼，成功后把服务端返回的完整称呼写回状态与缓存 */
  save: async (patch) => {
    const { names } = await saveSettings(patch);
    saveCache(names);
    set({ names, ready: true });
    return names;
  },
}));

/** 妈妈在界面上的名字（女儿给她起的昵称优先，没填昵称就用称呼） */
export function useMomName(): string {
  return displayName(useSettingsStore((s) => s.names), 'mom');
}

/** 女儿在界面上的名字（妈妈给她起的昵称优先，没填昵称就用称呼） */
export function useKidName(): string {
  return displayName(useSettingsStore((s) => s.names), 'kid');
}
