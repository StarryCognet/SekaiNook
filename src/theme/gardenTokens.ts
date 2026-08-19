/**
 * 阳光花园・学习乐园 —— 品牌设计令牌（紫色系）
 * 所有颜色/间距/圆角必须从此处读取，禁止硬编码。
 */
export const gardenTokens = {
  colors: {
    primary: '#B791FA', // 主色紫色
    primaryLight: '#C8A9FC', // 副标题淡紫色
    primarySoft: '#DCC9FD', // 选中菜单背景
    primaryBg: '#F3EDFF', // 淡紫背景
    bg: '#EAF3FF', // 浅蓝背景
    deepBlue: '#2B4A8C', // 深蓝状态卡
    sun: '#FFC53D', // 黄色阳光积分
    success: '#52C41A', // 绿色完成
    successBg: '#E8F8E8', // 淡绿完成背景
    rewardBg: '#FFF7E0', // 淡黄奖励区域
    white: '#FFFFFF',
    text: '#3A3A5C',
    textSecondary: '#8A8AA8',
    gray: '#C0C0D0', // 未获得勋章低饱和灰
  },
  spacing: {
    xs: 4,
    sm: 8,
    md: 16,
    lg: 24,
    xl: 32,
  },
  radius: {
    sm: 8,
    md: 12,
    lg: 16,
    full: 999,
  },
  shadow: {
    card: '0 4px 16px rgba(183, 145, 250, 0.15)',
    hover: '0 8px 24px rgba(183, 145, 250, 0.25)',
  },
} as const;