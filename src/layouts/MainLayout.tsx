import { useEffect, useRef, useState, type ReactNode } from "react";
import { Outlet, useLocation, useNavigate } from "react-router-dom";
import { Badge, Breadcrumb, Layout, Menu } from "antd";
import {
  AccountBookFilled,
  AccountBookOutlined,
  BellOutlined,
  BookOutlined,
  CalendarFilled,
  CalendarOutlined,
  HomeFilled,
  HomeOutlined,
  MoonOutlined,
  SettingFilled,
  SettingOutlined,
  SunFilled,
  SunOutlined,
  WalletOutlined,
} from "@ant-design/icons";
import { isMobile } from "../utils/device";
import {
  getScroll,
  getTabPath,
  rememberScroll,
  rememberTabPath,
  resolveTabRoot,
} from "../utils/tabMemory";
import { useFamilyStore } from "../store/useFamilyStore";
import { useNotificationStore } from "../store/useNotificationStore";
import { useSettingsStore } from "../store/useSettingsStore";
import { useThemePreset, useThemeStore } from "../store/useThemeStore";
import styles from "./MainLayout.module.css";

const { Sider, Header, Content } = Layout;

/** 面包屑尾项：按路径取名 */
const BREADCRUMB_MAP: Record<string, string> = {
  "/home": "首页",
  "/home/notifications": "通知",
  "/family": "家庭账本",
  "/family/plan": "学习计划",
  "/garden": "阳光花园・学习乐园",
  "/settings": "设置",
};

/**
 * 导航项：PC 侧边栏与手机底部 Tab 共用同一份数据。
 * 图标备了线框（未选中）与实心（选中）两套 —— 苹果的 tab 语汇是
 * 「未选中线框、选中实心」；Material 用背景药丸表示选中，不需要第二套图标。
 */
interface NavItem {
  key: string;
  icon: ReactNode;
  iconActive: ReactNode;
  label: string;
  shortLabel: string;
  /** 角标挂哪种计数：待审批（仅家长可见）或未读通知 */
  badge?: "pending" | "unread";
}

const NAV_ITEMS: NavItem[] = [
  {
    key: "/home",
    icon: <HomeOutlined />,
    iconActive: <HomeFilled />,
    label: "首页",
    shortLabel: "首页",
    badge: "unread",
  },
  {
    key: "/family",
    icon: <AccountBookOutlined />,
    iconActive: <AccountBookFilled />,
    label: "家庭账本",
    shortLabel: "账本",
    badge: "pending",
  },
  {
    key: "/family/plan",
    icon: <CalendarOutlined />,
    iconActive: <CalendarFilled />,
    label: "学习计划",
    shortLabel: "计划",
  },
  {
    key: "/garden",
    icon: <SunOutlined />,
    iconActive: <SunFilled />,
    label: "阳光花园",
    shortLabel: "花园",
  },
  {
    key: "/settings",
    icon: <SettingOutlined />,
    iconActive: <SettingFilled />,
    label: "设置",
    shortLabel: "设置",
  },
];

export default function MainLayout() {
  const navigate = useNavigate();
  const location = useLocation();
  const { role, pendingCount, balance } = useFamilyStore();
  const { audience, unreadCount, load: loadNotifications, refresh: refreshNotifications } =
    useNotificationStore();
  const loadNames = useSettingsStore((s) => s.load);
  const toggleBrightness = useThemeStore((s) => s.toggleBrightness);
  const themeDark = useThemePreset().dark;
  const [mobile, setMobile] = useState(isMobile());
  const [collapsed, setCollapsed] = useState(false);
  const contentRef = useRef<HTMLElement | null>(null);

  useEffect(() => {
    const handle = () => setMobile(isMobile());
    window.addEventListener("resize", handle);
    return () => window.removeEventListener("resize", handle);
  }, []);

  // 身份决定看哪一格信箱：家长看家长那格，小孩看小孩那格
  useEffect(() => {
    if (!role) return;
    loadNotifications(role === 'parent' ? 'parent' : 'child').catch(() => undefined);
  }, [role, loadNotifications]);

  // 家庭称呼（妈妈怎么叫女儿、女儿怎么叫妈妈）存在服务端，进 App 对一次，
  // 这样另一台手机改了称呼，这边刷新就能看到
  useEffect(() => {
    loadNames().catch(() => undefined);
  }, [loadNames]);

  // 未读通知轮询：放在主布局里而不是各页面 —— 不管停在哪一页，底部 Tab 的角标都要准。
  // 页面在后台（息屏 / 切走）时暂停，回到前台立刻补一次（省电，安卓上尤其重要）
  useEffect(() => {
    if (!audience) return;
    const refresh = () => {
      if (document.hidden) return;
      refreshNotifications().catch(() => undefined);
    };
    const timer = setInterval(refresh, 15000);
    const onVisible = () => {
      if (!document.hidden) refresh();
    };
    document.addEventListener('visibilitychange', onVisible);
    window.addEventListener('focus', onVisible);
    return () => {
      clearInterval(timer);
      document.removeEventListener('visibilitychange', onVisible);
      window.removeEventListener('focus', onVisible);
    };
  }, [audience, refreshNotifications]);

  const currentKey = location.pathname;
  const currentLabel = BREADCRUMB_MAP[currentKey] ?? "家庭工作台";
  /** 当前路径归属哪个 Tab（/garden 下的子页面也算在「花园」名下） */
  const activeTab = resolveTabRoot(currentKey);
  /** 当前 Tab 对应的导航项：移动端顶栏左侧借它的图标做「页面名胶囊」 */
  const activeNavItem = NAV_ITEMS.find((item) => item.key === activeTab) ?? NAV_ITEMS[0];

  // 记住每个 Tab 最后停留的路径：切走再切回来能直接回到原处
  useEffect(() => {
    rememberTabPath(currentKey);
  }, [currentKey]);

  // 按路径记录滚动位置（这是「每个 Tab 独立栈」里最容易丢的那一半）
  useEffect(() => {
    const el = contentRef.current;
    if (!el) return;
    let raf = 0;
    const onScroll = () => {
      if (raf) return;
      raf = requestAnimationFrame(() => {
        raf = 0;
        rememberScroll(location.pathname, el.scrollTop);
      });
    };
    el.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      el.removeEventListener("scroll", onScroll);
      if (raf) cancelAnimationFrame(raf);
    };
  }, [location.pathname, mobile]);

  // 恢复滚动位置：页面是懒加载的，首帧还没有高度，所以重试几帧；
  // 期间用户只要一动（触摸/滚轮）就立刻放弃，绝不跟人抢滚动条。
  useEffect(() => {
    const el = contentRef.current;
    if (!el) return;
    const target = getScroll(location.pathname);
    if (target <= 0) return;
    let frames = 0;
    let cancelled = false;
    const cancel = () => {
      cancelled = true;
    };
    el.addEventListener("wheel", cancel, { passive: true, once: true });
    el.addEventListener("touchstart", cancel, { passive: true, once: true });
    const step = () => {
      if (cancelled) return;
      el.scrollTop = target;
      frames += 1;
      if (Math.abs(el.scrollTop - target) > 1 && frames < 24) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
    return () => {
      cancelled = true;
      el.removeEventListener("wheel", cancel);
      el.removeEventListener("touchstart", cancel);
    };
  }, [location.pathname, mobile]);

  /** 回到内容区顶部（顺手把该路径的记忆清零，免得恢复时又弹回去） */
  const scrollToTop = (path: string) => {
    rememberScroll(path, 0);
    const el = contentRef.current;
    if (el) el.scrollTo({ top: 0, behavior: "smooth" });
  };

  /**
   * 点击导航：
   * - 点到别的 Tab → 回到它上次停留的路径（没有记录就回根路径）
   * - 再点当前 Tab → 回到该 Tab 的根页面并滚到顶（iOS 惯例，符合肌肉记忆）
   */
  const handleNavClick = (key: string) => {
    if (key === activeTab) {
      if (currentKey !== key) navigate(key);
      scrollToTop(key);
      return;
    }
    navigate(getTabPath(key) ?? key);
  };

  /**
   * Tab 角标：角标要挂在图标上（挂文字上语义不对，也容易错位）。
   * 家庭 Tab = 待审批数（只有家长需要处理），首页 Tab = 未读通知数。
   */
  const badgeCount = (item: NavItem): number => {
    if (item.badge === "pending") return role === "parent" ? pendingCount : 0;
    if (item.badge === "unread") return unreadCount;
    return 0;
  };

  const renderIcon = (item: NavItem, active: boolean) => {
    const node = active ? item.iconActive : item.icon;
    const count = badgeCount(item);
    return count > 0 ? (
      <Badge count={count} size="small" offset={[6, -2]}>
        {node}
      </Badge>
    ) : (
      node
    );
  };

  const menuItems = NAV_ITEMS.map((item) => ({
    key: item.key,
    icon: renderIcon(item, currentKey === item.key),
    label: item.label,
  }));

  const menu = (
    <Menu
      theme="dark"
      mode="inline"
      selectedKeys={[currentKey]}
      items={menuItems}
      onClick={({ key }) => handleNavClick(key)}
      style={{ background: "transparent" }}
    />
  );

  const logo = (
    <div className={styles.logo}>
      <span className={styles.logoIcon}>
        <BookOutlined />
      </span>
      {!collapsed && <span className={styles.logoText}>SekaiNook</span>}
    </div>
  );

  return (
    <Layout className={styles.rootLayout}>
      {!mobile && (
        <Sider
          collapsible
          collapsed={collapsed}
          onCollapse={setCollapsed}
          width={220}
          theme="dark"
          className={styles.sider}
        >
          {logo}
          {menu}
        </Sider>
      )}
      <Layout className={styles.mainLayout}>
        <Header className={styles.header}>
          {mobile ? (
            /* 移动端顶栏左侧：小图标块 + 当前页名（面包屑在手机上太啰嗦） */
            <span className={styles.pageChip}>
              <span className={styles.pageChipIcon}>{renderIcon(activeNavItem, true)}</span>
              <span className={styles.pageChipLabel}>{currentLabel}</span>
            </span>
          ) : (
            <Breadcrumb items={[{ title: "SekaiNook" }, { title: currentLabel }]} />
          )}
          <div className={styles.headerActions}>
            {/* 余额小胶囊：只在电脑端 —— 手机上首页与账本都有更大的余额卡，
                顶栏再塞一个会把左边的页面名挤没 */}
            {!mobile && (
              <button
                type="button"
                className={styles.balanceChip}
                onClick={() => navigate("/family")}
                title="去家庭账本"
              >
                <WalletOutlined />
                <span className={`num ${styles.balanceChipNum}`}>{balance}</span>
              </button>
            )}
            {/* 通知铃铛：未读挂角标，停在任何一页都能一键到通知页 */}
            <button
              type="button"
              className={styles.iconChip}
              onClick={() => navigate("/home/notifications")}
              title="通知"
              aria-label={unreadCount > 0 ? `通知，${unreadCount} 条未读` : "通知"}
            >
              {unreadCount > 0 ? (
                <Badge count={unreadCount} size="small" offset={[2, -2]}>
                  <BellOutlined />
                </Badge>
              ) : (
                <BellOutlined />
              )}
            </button>
            {/* 深浅开关：太阳与月亮都摆在明面上，滑块托着当前这一档；
                点另一档 = 切到「上次用的」那种深浅（与原来那颗圆按钮同一份记忆） */}
            <div
              className={styles.brightnessSwitch}
              data-dark={themeDark ? "true" : "false"}
              role="group"
              aria-label="深浅主题"
            >
              <span className={styles.brightnessKnob} aria-hidden="true" />
              <button
                type="button"
                className={styles.brightnessOption}
                aria-pressed={!themeDark}
                aria-label="切到浅色主题"
                title="浅色"
                onClick={() => {
                  if (themeDark) toggleBrightness();
                }}
              >
                <SunOutlined />
              </button>
              <button
                type="button"
                className={styles.brightnessOption}
                aria-pressed={themeDark}
                aria-label="切到深色主题"
                title="深色"
                onClick={() => {
                  if (!themeDark) toggleBrightness();
                }}
              >
                <MoonOutlined />
              </button>
            </div>
          </div>
        </Header>
        <Content className={styles.content} ref={contentRef}>
          <div className="page-transition">
            <Outlet />
          </div>
        </Content>
      </Layout>
      {mobile && (
        <nav className={styles.bottomNav} aria-label="主导航">
          {NAV_ITEMS.map((item) => {
            const active = item.key === activeTab;
            return (
              <button
                key={item.key}
                type="button"
                className={`${styles.bottomNavItem} ${active ? styles.bottomNavItemActive : ""}`}
                onClick={() => handleNavClick(item.key)}
                aria-label={item.label}
                aria-current={active ? "page" : undefined}
              >
                <span className={styles.bottomNavIcon}>{renderIcon(item, active)}</span>
                <span className={styles.bottomNavLabel}>{item.shortLabel}</span>
              </button>
            );
          })}
        </nav>
      )}
    </Layout>
  );
}
