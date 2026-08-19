import {
  BookOutlined,
  ReadOutlined,
  CalculatorOutlined,
  HomeOutlined,
  EyeOutlined,
  ThunderboltOutlined,
  EditOutlined,
  SunOutlined,
  SmileOutlined,
  CalendarOutlined,
  TrophyOutlined,
  EnvironmentOutlined,
  GoldOutlined,
  DashboardOutlined,
  CheckCircleOutlined,
  ShoppingOutlined,
  HistoryOutlined,
  StarOutlined,
} from '@ant-design/icons';
import type { ReactNode } from 'react';

/** 图标 key -> 图标组件 映射 */
const ICON_MAP: Record<string, ReactNode> = {
  book: <BookOutlined />,
  read: <ReadOutlined />,
  calc: <CalculatorOutlined />,
  'book-open': <ReadOutlined />,
  pen: <EditOutlined />,
  eye: <EyeOutlined />,
  sport: <ThunderboltOutlined />,
  home: <HomeOutlined />,
  sun: <SunOutlined />,
  flower: <SmileOutlined />,
  calendar: <CalendarOutlined />,
  trophy: <TrophyOutlined />,
  feather: <EditOutlined />,
  leaf: <EnvironmentOutlined />,
  coin: <GoldOutlined />,
  dashboard: <DashboardOutlined />,
  check: <CheckCircleOutlined />,
  shop: <ShoppingOutlined />,
  history: <HistoryOutlined />,
  star: <StarOutlined />,
};

/** 根据 key 获取图标，未知 key 返回默认图标 */
export function getGardenIcon(key: string): ReactNode {
  return ICON_MAP[key] ?? <StarOutlined />;
}