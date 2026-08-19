import type { ThemeConfig } from 'antd';

/**
 * 设计令牌 —— 唯一数据源。
 * 所有颜色/间距/圆角/阴影/字体必须从此处读取，禁止在组件中硬编码 hex/px。
 */
export const designTokens = {
  colors: {
    primary: '#1A1A2E',
    primaryLight: '#2A2A4A',
    success: '#0F9B6C',
    danger: '#E94560',
    warning: '#F5A623',
    bg: '#F5F6FA',
    surface: '#FFFFFF',
    text: '#1A1A2E',
    textSecondary: '#6B7280',
    border: '#E5E7EB',
    white: '#FFFFFF',
  },
  spacing: {
    xs: 4,
    sm: 8,
    md: 16,
    lg: 24,
    xl: 32,
  },
  radius: {
    sm: 6,
    md: 10,
    lg: 16,
    full: 999,
  },
  shadow: {
    card: '0 2px 12px rgba(26, 26, 46, 0.08)',
    hover: '0 6px 20px rgba(26, 26, 46, 0.14)',
  },
  font: {
    family:
      "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei', sans-serif",
    num: "'Oswald', 'Segoe UI', sans-serif",
    sizeXs: 12,
    sizeSm: 14,
    sizeMd: 16,
    sizeLg: 20,
    sizeXl: 24,
    sizeNum: 48,
  },
} as const;

/** antd 主题映射（供 ConfigProvider 使用） */
export const antdTheme: ThemeConfig = {
  token: {
    colorPrimary: designTokens.colors.primary,
    colorSuccess: designTokens.colors.success,
    colorError: designTokens.colors.danger,
    colorWarning: designTokens.colors.warning,
    colorBgLayout: designTokens.colors.bg,
    colorTextBase: designTokens.colors.text,
    colorBorder: designTokens.colors.border,
    borderRadius: designTokens.radius.md,
    fontFamily: designTokens.font.family,
  },
  components: {
    Layout: {
      siderBg: designTokens.colors.primary,
      headerBg: designTokens.colors.surface,
      headerHeight: 56,
    },
    Menu: {
      darkItemBg: designTokens.colors.primary,
      darkItemSelectedBg: designTokens.colors.primaryLight,
    },
    Card: {
      borderRadiusLG: designTokens.radius.lg,
    },
  },
};