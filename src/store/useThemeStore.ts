/**
 * 主题与全局背景图的状态。
 *
 * 两件事放在一起是因为它们都影响「整个 App 长什么样」，也都由设置页控制：
 *   - themeId：主题（原始 / 午夜蓝），存本机 localStorage —— 每台设备各选各的；
 *   - background：全局背景图地址，存服务端 settings 表 —— 两台设备看到同一张，
 *     而且服务端知道它被引用，不会被「闲置照片清理」误删。
 *
 * 真正的上色在 App.tsx：把 themeId 写到 <html data-theme>，把图片写到 --app-bg-image。
 */

import { create } from 'zustand';
import { fetchSettings, saveSettings } from '../api/settings';
import {
  DEFAULT_THEME_ID,
  THEME_STORAGE_KEY,
  isThemeId,
  themePreset,
  type ThemeId,
  type ThemePalette,
  type ThemePreset,
} from '../theme/themes';

function loadThemeId(): ThemeId {
  try {
    const raw = localStorage.getItem(THEME_STORAGE_KEY);
    return isThemeId(raw) ? raw : DEFAULT_THEME_ID;
  } catch {
    return DEFAULT_THEME_ID;
  }
}

function saveThemeId(id: ThemeId): void {
  try {
    localStorage.setItem(THEME_STORAGE_KEY, id);
  } catch {
    // 隐私模式：存不住也没关系，本次会话内仍然生效
  }
}

interface ThemeState {
  themeId: ThemeId;
  /** 全局背景图地址，'' = 没设 */
  background: string;
  /** 背景图是否已问过服务端（避免首屏先铺一层纯色再跳成照片） */
  backgroundReady: boolean;
  setThemeId: (id: ThemeId) => void;
  /** 打开 App 时问一次服务端要背景图；失败就当没设，不打扰用户 */
  loadBackground: () => Promise<void>;
  /** 设置 / 更换 / 移除背景图（传 '' 表示移除） */
  saveBackground: (url: string) => Promise<string>;
}

export const useThemeStore = create<ThemeState>((set) => ({
  themeId: loadThemeId(),
  background: '',
  backgroundReady: false,

  setThemeId: (id) => {
    saveThemeId(id);
    set({ themeId: id });
  },

  loadBackground: async () => {
    try {
      const { background } = await fetchSettings();
      set({ background: background ?? '', backgroundReady: true });
    } catch {
      set({ backgroundReady: true });
    }
  },

  saveBackground: async (url) => {
    const { background } = await saveSettings({ background: url });
    const next = background ?? '';
    set({ background: next, backgroundReady: true });
    return next;
  },
}));

/** 当前主题预设（颜色、是否深色、设置页预览色） */
export function useThemePreset(): ThemePreset {
  return themePreset(useThemeStore((s) => s.themeId));
}

/** 当前主题的调色板：给 CSS 变量到不了的 TS 场景用（图表轴、图标色） */
export function useThemePalette(): ThemePalette {
  return useThemePreset().palette;
}
