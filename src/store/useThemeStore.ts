/**
 * 主题与全局背景图的状态。
 *
 * 两件事放在一起是因为它们都影响「整个 App 长什么样」，也都由设置页控制：
 *   - themeId：主题（七套：原始 / 午夜蓝 / 暗夜红 / 樱花粉 / 森林绿 / 暖阳橙 / P3R 午夜蓝），
 *     存本机 localStorage —— 每台设备各选各的；右上角那颗太阳/月亮按钮也走这里，
 *     它在你「上次用的浅色」与「上次用的深色」之间来回切，同样记在本机；
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

/**
 * 深浅两格里各自「上次用过的那套」。
 * 右上角一键切换要的是「深 ⇄ 浅」这个动作，而不是固定跳某一套：
 * 你白天用樱花粉、晚上用暗夜红，那颗按钮就正好在这两套之间来回。
 */
const LAST_LIGHT_KEY = 'sekainook_theme_light';
const LAST_DARK_KEY = 'sekainook_theme_dark';

function rememberBrightness(id: ThemeId): void {
  try {
    localStorage.setItem(themePreset(id).dark ? LAST_DARK_KEY : LAST_LIGHT_KEY, id);
  } catch {
    // 记不住就退回出厂的那套深浅主题
  }
}

function loadBrightness(dark: boolean): ThemeId {
  const fallback: ThemeId = dark ? 'midnight' : DEFAULT_THEME_ID;
  try {
    const raw = localStorage.getItem(dark ? LAST_DARK_KEY : LAST_LIGHT_KEY);
    if (isThemeId(raw) && themePreset(raw).dark === dark) return raw;
  } catch {
    // 读不到就用出厂值
  }
  return fallback;
}

interface ThemeState {
  themeId: ThemeId;
  /** 全局背景图地址，'' = 没设 */
  background: string;
  /** 背景图是否已问过服务端（避免首屏先铺一层纯色再跳成照片） */
  backgroundReady: boolean;
  setThemeId: (id: ThemeId) => void;
  /** 深浅一键切换（右上角那颗按钮）：在你上次用的浅色与深色之间来回 */
  toggleBrightness: () => void;
  /** 打开 App 时问一次服务端要背景图；失败就当没设，不打扰用户 */
  loadBackground: () => Promise<void>;
  /** 设置 / 更换 / 移除背景图（传 '' 表示移除） */
  saveBackground: (url: string) => Promise<string>;
}

export const useThemeStore = create<ThemeState>((set, get) => {
  const initialThemeId = loadThemeId();
  // 首屏就把当前这套登记进它所属的深/浅格，免得第一次点切换时没有可回的目标
  rememberBrightness(initialThemeId);

  return {
    themeId: initialThemeId,
    background: '',
    backgroundReady: false,

    setThemeId: (id) => {
      saveThemeId(id);
      rememberBrightness(id);
      set({ themeId: id });
    },

    toggleBrightness: () => {
      const next = loadBrightness(!themePreset(get().themeId).dark);
      saveThemeId(next);
      rememberBrightness(next);
      set({ themeId: next });
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
  };
});

/** 当前主题预设（颜色、是否深色、设置页预览色） */
export function useThemePreset(): ThemePreset {
  return themePreset(useThemeStore((s) => s.themeId));
}

/** 当前主题的调色板：给 CSS 变量到不了的 TS 场景用（图表轴、图标色） */
export function useThemePalette(): ThemePalette {
  return useThemePreset().palette;
}
