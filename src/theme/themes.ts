import { theme as antdThemeApi, type ThemeConfig } from 'antd';
import { designTokens } from './tokens';

/**
 * 主题预设 —— 设置页「外观」里的主题切换，全局生效。
 *
 * 一套主题 = 两半：
 *   ① CSS 变量集（写在 theme/global.css 的 :root[data-theme='xxx'] 里，页面样式全读变量）
 *   ② antd 主题（下面 buildAntdTheme，管 antd 组件的底色/文字/描边）
 * 两半必须一起换，否则会出现「页面是深色、弹窗还是白色」这种断层。
 *
 * 默认主题是 original（原始浅色），出厂什么都不用设。
 */

export type ThemeId = 'original' | 'midnight';

/** 供 TS 里用颜色（图表轴、图标等，CSS 变量到不了的地方） */
export interface ThemePalette {
  primary: string;
  success: string;
  danger: string;
  warning: string;
  bg: string;
  surface: string;
  text: string;
  textSecondary: string;
  border: string;
}

export interface ThemePreset {
  id: ThemeId;
  /** 设置页显示的名字 */
  name: string;
  /** 设置页显示的一句话说明 */
  description: string;
  /** 预览小块用的三个色（底 / 卡片 / 强调） */
  swatch: [string, string, string];
  /** 是否深色主题（决定 antd 走不走暗色算法） */
  dark: boolean;
  palette: ThemePalette;
}

export const THEMES: readonly ThemePreset[] = [
  {
    id: 'original',
    name: '原始',
    description: '浅色卡片 + 深蓝主色，出厂默认',
    swatch: ['#f5f6fa', '#ffffff', '#1a1a2e'],
    dark: false,
    palette: {
      primary: designTokens.colors.primary,
      success: designTokens.colors.success,
      danger: designTokens.colors.danger,
      warning: designTokens.colors.warning,
      bg: designTokens.colors.bg,
      surface: designTokens.colors.surface,
      text: designTokens.colors.text,
      textSecondary: designTokens.colors.textSecondary,
      border: designTokens.colors.border,
    },
  },
  {
    id: 'midnight',
    name: '午夜蓝',
    description: '午夜蓝墨底 + 青蓝高光，晚上看不刺眼',
    swatch: ['#060c1c', '#0e1a33', '#2b7fe0'],
    dark: true,
    palette: {
      primary: '#2b7fe0',
      success: '#34d399',
      danger: '#ff6b81',
      warning: '#f7b955',
      bg: '#060c1c',
      surface: '#0e1a33',
      text: '#e8f1ff',
      textSecondary: '#92a8c9',
      border: '#22355a',
    },
  },
];

export const DEFAULT_THEME_ID: ThemeId = 'original';

/** 主题选择存在本机（每台设备各选各的，不跨设备同步） */
export const THEME_STORAGE_KEY = 'sekainook_theme';

export function isThemeId(value: unknown): value is ThemeId {
  return value === 'original' || value === 'midnight';
}

export function themePreset(id: ThemeId): ThemePreset {
  return THEMES.find((item) => item.id === id) ?? THEMES[0];
}

/**
 * 组装 antd 主题。
 * hasBackground = 用户设了自定义背景图：卡片与底色要半透明，让照片透出来。
 */
export function buildAntdTheme(id: ThemeId, hasBackground = false): ThemeConfig {
  const preset = themePreset(id);
  const { palette } = preset;

  const surface = hasBackground
    ? preset.dark
      ? 'rgba(14, 26, 51, 0.82)'
      : 'rgba(255, 255, 255, 0.82)'
    : palette.surface;

  return {
    algorithm: preset.dark ? antdThemeApi.darkAlgorithm : antdThemeApi.defaultAlgorithm,
    token: {
      colorPrimary: palette.primary,
      colorSuccess: palette.success,
      colorError: palette.danger,
      colorWarning: palette.warning,
      colorBgLayout: hasBackground ? 'transparent' : palette.bg,
      colorBgContainer: surface,
      colorTextBase: palette.text,
      colorBorder: palette.border,
      borderRadius: designTokens.radius.md,
      fontFamily: designTokens.font.family,
    },
    components: {
      Layout: {
        siderBg: preset.dark ? '#04091a' : designTokens.colors.primary,
        headerBg: surface,
        headerHeight: 56,
        bodyBg: hasBackground ? 'transparent' : palette.bg,
      },
      Menu: {
        darkItemBg: preset.dark ? '#04091a' : designTokens.colors.primary,
        darkItemSelectedBg: preset.dark ? '#152a52' : designTokens.colors.primaryLight,
      },
      Card: {
        borderRadiusLG: designTokens.radius.lg,
        colorBgContainer: surface,
      },
      Segmented: {
        itemSelectedBg: preset.dark ? '#1d3160' : palette.surface,
      },
    },
  };
}
