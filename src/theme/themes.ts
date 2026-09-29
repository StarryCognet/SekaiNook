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
 * 加新主题的步骤（两处都要动，别漏）：
 *   ① 这里：ThemeId 加 id、THEMES 加一条（palette 全字段 + swatch + dark）
 *   ② theme/global.css：加一段 :root[data-theme='新id'] { ... }，字段与其它主题对齐
 *
 * 默认主题是 original（原始浅色），出厂什么都不用设。
 */

export type ThemeId = 'original' | 'midnight' | 'sakura' | 'forest' | 'sunset' | 'crimson';

/** 供 TS 里用颜色（图表轴、图标等，CSS 变量到不了的地方） */
export interface ThemePalette {
  primary: string;
  /** 主色的浅一档，用于渐变尾、选中底色 */
  primarySoft: string;
  success: string;
  danger: string;
  warning: string;
  bg: string;
  surface: string;
  surfaceSoft: string;
  text: string;
  textSecondary: string;
  textTertiary: string;
  border: string;
  /** PC 侧边栏 / 暗色菜单的底 */
  sider: string;
  /** 侧边栏与暗色菜单的选中项底 */
  siderSelected: string;
  /** antd Segmented 选中项底 */
  segmentedSelected: string;
  /** 设了自定义背景图时的半透明卡片底（照片透出来） */
  surfaceGlass: string;
  /** 设了自定义背景图时的半透明次级底 */
  surfaceSoftGlass: string;
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

const GLASS_LIGHT = 'rgba(255, 255, 255, 0.82)';
const GLASS_SOFT_LIGHT = 'rgba(255, 255, 255, 0.7)';

export const THEMES: readonly ThemePreset[] = [
  {
    id: 'original',
    name: '原始',
    description: '浅色卡片 + 深蓝主色，出厂默认',
    swatch: ['#f5f6fa', '#ffffff', '#1a1a2e'],
    dark: false,
    palette: {
      primary: designTokens.colors.primary,
      primarySoft: designTokens.colors.primaryLight,
      success: designTokens.colors.success,
      danger: designTokens.colors.danger,
      warning: designTokens.colors.warning,
      bg: designTokens.colors.bg,
      surface: designTokens.colors.surface,
      surfaceSoft: '#f9fafb',
      text: designTokens.colors.text,
      textSecondary: designTokens.colors.textSecondary,
      textTertiary: '#9ca3af',
      border: designTokens.colors.border,
      sider: designTokens.colors.primary,
      siderSelected: designTokens.colors.primaryLight,
      segmentedSelected: designTokens.colors.surface,
      surfaceGlass: GLASS_LIGHT,
      surfaceSoftGlass: GLASS_SOFT_LIGHT,
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
      primarySoft: '#1b4a8f',
      success: '#34d399',
      danger: '#ff6b81',
      warning: '#f7b955',
      bg: '#060c1c',
      surface: '#0e1a33',
      surfaceSoft: '#132241',
      text: '#e8f1ff',
      textSecondary: '#92a8c9',
      textTertiary: '#6c82a5',
      border: '#22355a',
      sider: '#04091a',
      siderSelected: '#152a52',
      segmentedSelected: '#1d3160',
      surfaceGlass: 'rgba(14, 26, 51, 0.82)',
      surfaceSoftGlass: 'rgba(19, 34, 65, 0.7)',
    },
  },
  {
    id: 'sakura',
    name: '樱花粉',
    description: '奶粉底 + 樱花主色，软软的一天',
    swatch: ['#fff5f8', '#ffffff', '#e8628f'],
    dark: false,
    palette: {
      primary: '#e8628f',
      primarySoft: '#f6a8c4',
      success: '#2fae86',
      danger: '#e8455f',
      warning: '#e9a13a',
      bg: '#fff5f8',
      surface: '#ffffff',
      surfaceSoft: '#fdf1f5',
      text: '#3b2430',
      textSecondary: '#8b6b78',
      textTertiary: '#b39aa4',
      border: '#f6dbe5',
      sider: '#e8628f',
      siderSelected: '#c9426e',
      segmentedSelected: '#ffffff',
      surfaceGlass: GLASS_LIGHT,
      surfaceSoftGlass: GLASS_SOFT_LIGHT,
    },
  },
  {
    id: 'forest',
    name: '森林绿',
    description: '薄荷底 + 森林绿，清清爽爽像早上',
    swatch: ['#f2f9f5', '#ffffff', '#2f9e6e'],
    dark: false,
    palette: {
      primary: '#2f9e6e',
      primarySoft: '#8fd3b4',
      success: '#2f9e6e',
      danger: '#e0603f',
      warning: '#dfa03a',
      bg: '#f2f9f5',
      surface: '#ffffff',
      surfaceSoft: '#eef7f1',
      text: '#1e3b2f',
      textSecondary: '#5f7d6f',
      textTertiary: '#93ab9f',
      border: '#dcebe2',
      sider: '#1f6f4d',
      siderSelected: '#2f9e6e',
      segmentedSelected: '#ffffff',
      surfaceGlass: GLASS_LIGHT,
      surfaceSoftGlass: GLASS_SOFT_LIGHT,
    },
  },
  {
    id: 'sunset',
    name: '暖阳橙',
    description: '米白底 + 暖橙主色，像傍晚的客厅',
    swatch: ['#fff8f1', '#ffffff', '#e07b39'],
    dark: false,
    palette: {
      primary: '#e07b39',
      primarySoft: '#f5b183',
      success: '#3d9e6d',
      danger: '#d8452f',
      warning: '#dd9a2a',
      bg: '#fff8f1',
      surface: '#ffffff',
      surfaceSoft: '#fdf3e9',
      text: '#3f2a1b',
      textSecondary: '#8a6c55',
      textTertiary: '#b39b86',
      border: '#f4e0cc',
      sider: '#c25f22',
      siderSelected: '#e07b39',
      segmentedSelected: '#ffffff',
      surfaceGlass: GLASS_LIGHT,
      surfaceSoftGlass: GLASS_SOFT_LIGHT,
    },
  },
  {
    id: 'crimson',
    name: '暗夜红',
    description: '墨红底 + 霓虹红，像游戏界面（夜里护眼）',
    swatch: ['#140609', '#1f0c11', '#f04a5a'],
    dark: true,
    palette: {
      primary: '#f04a5a',
      primarySoft: '#8c1f2d',
      success: '#3ddc97',
      danger: '#ff7b7b',
      warning: '#f2b44c',
      bg: '#140609',
      surface: '#1f0c11',
      surfaceSoft: '#2a1218',
      text: '#f8ecef',
      textSecondary: '#c99aa5',
      textTertiary: '#9c7079',
      border: '#3d2027',
      sider: '#0d0406',
      siderSelected: '#3a1620',
      segmentedSelected: '#3a1620',
      surfaceGlass: 'rgba(31, 12, 17, 0.82)',
      surfaceSoftGlass: 'rgba(42, 18, 24, 0.7)',
    },
  },
];

export const DEFAULT_THEME_ID: ThemeId = 'original';

/** 主题选择存在本机（每台设备各选各的，不跨设备同步） */
export const THEME_STORAGE_KEY = 'sekainook_theme';

export function isThemeId(value: unknown): value is ThemeId {
  return THEMES.some((item) => item.id === value);
}

export function themePreset(id: ThemeId): ThemePreset {
  return THEMES.find((item) => item.id === id) ?? THEMES[0];
}

/**
 * 组装 antd 主题。
 * hasBackground = 用户设了自定义背景图：卡片与底色要半透明，让照片透出来。
 * 颜色一律取自 palette，这里不再出现任何写死的色值 —— 加主题只要加一条 THEMES。
 */
export function buildAntdTheme(id: ThemeId, hasBackground = false): ThemeConfig {
  const preset = themePreset(id);
  const { palette } = preset;

  const surface = hasBackground ? palette.surfaceGlass : palette.surface;

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
        siderBg: palette.sider,
        headerBg: surface,
        headerHeight: 56,
        bodyBg: hasBackground ? 'transparent' : palette.bg,
      },
      Menu: {
        darkItemBg: palette.sider,
        darkItemSelectedBg: palette.siderSelected,
      },
      Card: {
        borderRadiusLG: designTokens.radius.lg,
        colorBgContainer: surface,
      },
      Segmented: {
        itemSelectedBg: palette.segmentedSelected,
      },
    },
  };
}
