import { useEffect, useState, type ReactNode } from "react";
import { Outlet, useLocation, useNavigate } from "react-router-dom";
import { Layout, Menu, Breadcrumb, Badge } from "antd";
import { HomeOutlined, CalendarOutlined, BookOutlined, SunOutlined, SettingOutlined } from "@ant-design/icons";
import { isMobile } from "../utils/device";
import { useFamilyStore } from "../store/useFamilyStore";
import styles from "./MainLayout.module.css";

const { Sider, Header, Content } = Layout;

/** 面包屑映射 */
const BREADCRUMB_MAP: Record<string, string> = {
  "/family": "家庭工作台",
  "/family/plan": "学习计划",
  "/garden": "阳光花园・学习乐园",
  "/settings": "设置",
};

/** 导航项：PC 侧边栏与移动端底部 Tab 共用同一份数据 */
interface NavItem {
  key: string;
  icon: ReactNode;
  /** 侧边栏用完整名称 */
  label: string;
  /** 底部 Tab 用短名称（窄屏放不下完整名称） */
  shortLabel: string;
  /** 是否展示待审批角标 */
  withBadge?: boolean;
}

const NAV_ITEMS: NavItem[] = [
  { key: "/family", icon: <HomeOutlined />, label: "家庭工作台", shortLabel: "家庭", withBadge: true },
  { key: "/family/plan", icon: <CalendarOutlined />, label: "学习计划", shortLabel: "计划" },
  { key: "/garden", icon: <SunOutlined />, label: "阳光花园", shortLabel: "花园" },
  { key: "/settings", icon: <SettingOutlined />, label: "设置", shortLabel: "设置" },
];

/** 主布局：PC 固定侧边栏 + 顶栏；移动端改为底部 Tab 栏 */
export default function MainLayout() {
  const navigate = useNavigate();
  const location = useLocation();
  const { role, pendingCount } = useFamilyStore();
  const [mobile, setMobile] = useState(isMobile());
  const [collapsed, setCollapsed] = useState(false);

  useEffect(() => {
    const handle = () => setMobile(isMobile());
    window.addEventListener("resize", handle);
    return () => window.removeEventListener("resize", handle);
  }, []);

  const currentKey = location.pathname;
  const currentLabel = BREADCRUMB_MAP[currentKey] ?? "家庭工作台";

  const handleMenuClick = (key: string) => {
    navigate(key);
  };

  /** 家长端「家庭工作台」显示待审批角标 */
  const showPendingBadge = (item: NavItem) =>
    Boolean(item.withBadge) && role === "parent" && pendingCount > 0;

  /** 侧边栏菜单项 */
  const menuItems = NAV_ITEMS.map((item) => ({
    key: item.key,
    icon: item.icon,
    label: showPendingBadge(item) ? (
      <Badge count={pendingCount} size="small" offset={[8, 0]}>
        {item.label}
      </Badge>
    ) : (
      item.label
    ),
  }));

  const menu = (
    <Menu
      theme="dark"
      mode="inline"
      selectedKeys={[currentKey]}
      items={menuItems}
      onClick={({ key }) => handleMenuClick(key)}
      style={{ background: "transparent" }}
    />
  );

  const logo = (
    <div className={`${styles.logo} ${collapsed ? styles.logoCollapsed : ""}`}>
      <span className={styles.logoIcon}>
        <BookOutlined />
      </span>
      {!collapsed && <span className={styles.logoText}>SekaiNook</span>}
    </div>
  );

  return (
    <Layout className={styles.rootLayout}>
      {/* PC 固定侧边栏 */}
      {!mobile && (
        <Sider collapsible collapsed={collapsed} onCollapse={setCollapsed} width={220} theme="dark" className={styles.sider}>
          {logo}
          {menu}
        </Sider>
      )}

      {/* 右侧：固定顶栏 + 可滚动内容区 */}
      <Layout className={styles.mainLayout}>
        <Header className={styles.header}>
          <Breadcrumb items={[{ title: "SekaiNook" }, { title: currentLabel }]} />
        </Header>

        <Content className={styles.content}>
          <div className="page-transition">
            <Outlet />
          </div>
        </Content>
      </Layout>

      {/* 移动端底部 Tab 栏：拇指可达，比原来的汉堡菜单少一次点击 */}
      {mobile && (
        <nav className={styles.bottomNav}>
          {NAV_ITEMS.map((item) => {
            const active = currentKey === item.key;
            return (
              <button
                key={item.key}
                type="button"
                className={`${styles.bottomNavItem} ${active ? styles.bottomNavItemActive : ""}`}
                onClick={() => handleMenuClick(item.key)}
                aria-label={item.label}
                aria-current={active ? "page" : undefined}
              >
                <span className={styles.bottomNavIcon}>
                  {showPendingBadge(item) ? (
                    <Badge count={pendingCount} size="small">
                      {item.icon}
                    </Badge>
                  ) : (
                    item.icon
                  )}
                </span>
                <span className={styles.bottomNavLabel}>{item.shortLabel}</span>
              </button>
            );
          })}
        </nav>
      )}
    </Layout>
  );
}
