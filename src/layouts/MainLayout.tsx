import { useEffect, useState } from 'react';
import { Outlet, useLocation, useNavigate } from 'react-router-dom';
import { Layout, Menu, Drawer, Button, Breadcrumb } from 'antd';
import {
  HomeOutlined,
  CalendarOutlined,
  MenuOutlined,
  BookOutlined,
  SunOutlined,
} from '@ant-design/icons';
import { isMobile } from '../utils/device';
import { getCurrentWeekLabel } from '../utils/week';
import { designTokens } from '../theme/tokens';
import styles from './MainLayout.module.css';

const { Sider, Header, Content } = Layout;

/** 侧边栏菜单项 */
const MENU_ITEMS = [
  { key: '/family', icon: <HomeOutlined />, label: '家庭工作台' },
  { key: '/family/plan', icon: <CalendarOutlined />, label: '学习计划' },
  { key: '/garden', icon: <SunOutlined />, label: '阳光花园' },
];

/** 面包屑映射 */
const BREADCRUMB_MAP: Record<string, string> = {
  '/family': '家庭工作台',
  '/family/plan': '学习计划',
  '/garden': '阳光花园・学习乐园',
};

/** 主布局：PC 侧边栏 + 顶栏；移动端折叠为 Drawer */
export default function MainLayout() {
  const navigate = useNavigate();
  const location = useLocation();
  const [mobile, setMobile] = useState(isMobile());
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [collapsed, setCollapsed] = useState(false);

  useEffect(() => {
    const handle = () => setMobile(isMobile());
    window.addEventListener('resize', handle);
    return () => window.removeEventListener('resize', handle);
  }, []);

  const currentKey = location.pathname;
  const currentLabel = BREADCRUMB_MAP[currentKey] ?? '家庭工作台';

  const handleMenuClick = (key: string) => {
    navigate(key);
    setDrawerOpen(false);
  };

  const menu = (
    <Menu
      theme="dark"
      mode="inline"
      selectedKeys={[currentKey]}
      items={MENU_ITEMS}
      onClick={({ key }) => handleMenuClick(key)}
      style={{ background: 'transparent' }}
    />
  );

  const logo = (
    <div className={styles.logo}>
      <span className={styles.logoIcon}>
        <BookOutlined />
      </span>
      <span className={styles.logoText}>SekaiNook</span>
    </div>
  );

  return (
    <Layout style={{ minHeight: '100vh' }}>
      {/* PC 侧边栏 */}
      {!mobile && (
        <Sider
          collapsible
          collapsed={collapsed}
          onCollapse={setCollapsed}
          width={220}
          theme="dark"
        >
          {logo}
          {menu}
        </Sider>
      )}

      {/* 移动端 Drawer */}
      {mobile && (
        <Drawer
          placement="left"
          open={drawerOpen}
          onClose={() => setDrawerOpen(false)}
          size={220}
          styles={{ body: { padding: 0, background: designTokens.colors.primary } }}
          closable={false}
        >
          {logo}
          {menu}
        </Drawer>
      )}

      <Layout>
        <Header
          style={{
            background: designTokens.colors.surface,
            padding: `0 ${designTokens.spacing.md}px`,
            display: 'flex',
            alignItems: 'center',
            gap: designTokens.spacing.md,
            borderBottom: `1px solid ${designTokens.colors.border}`,
          }}
        >
          {mobile && (
            <Button
              type="text"
              icon={<MenuOutlined />}
              onClick={() => setDrawerOpen(true)}
            />
          )}
          <Breadcrumb
            items={[{ title: 'SekaiNook' }, { title: currentLabel }]}
          />
          <div style={{ flex: 1 }} />
          <span
            className={`num ${styles.weekLabel}`}
            style={{ color: designTokens.colors.primary }}
          >
            {getCurrentWeekLabel()}
          </span>
        </Header>

        <Content style={{ padding: designTokens.spacing.lg }}>
          <div className="page-transition">
            <Outlet />
          </div>
        </Content>
      </Layout>
    </Layout>
  );
}