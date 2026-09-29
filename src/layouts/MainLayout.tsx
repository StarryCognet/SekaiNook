import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
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
  /** 往下滑看内容时把顶栏与底部 Tab 栏收起来，往上滑再放出来 */
  const [chromeHidden, setChromeHidden] = useState(false);
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

  /**
   * 底部 Tab 的选中高光是一条会「滑过去」的胶囊：
   * 量出当前项在栏里的 left / width，交给 CSS 用带过冲的弹簧曲线做位移。
   * 量出来而不是按「1/5 宽度」算，是为了以后改边距、加第 6 个 Tab 也不会错位。
   */
  const bottomNavRef = useRef<HTMLElement | null>(null);
  const navItemRefs = useRef<Record<string, HTMLButtonElement | null>>({});
  const [navPill, setNavPill] = useState<{ x: number; w: number } | null>(null);

  useLayoutEffect(() => {
    if (!mobile) return;
    const measure = () => {
      const nav = bottomNavRef.current;
      const active = navItemRefs.current[activeTab];
      if (!nav || !active) return;
      const navBox = nav.getBoundingClientRect();
      const box = active.getBoundingClientRect();
      setNavPill({ x: box.left - navBox.left, w: box.width });
    };
    measure();
    window.addEventListener("resize", measure);
    window.addEventListener("orientationchange", measure);
    return () => {
      window.removeEventListener("resize", measure);
      window.removeEventListener("orientationchange", measure);
    };
  }, [activeTab, mobile]);

  /**
   * 长按「拿起来」换 Tab（手机上）：
   * - 短按：照旧直接切（走按钮的 onClick）。
   * - 长按：被按住的那一项放大，玻璃高光跟着手指走，松手落到哪一项就切到哪一项。
   * 拖动期间高光不吃 CSS 过渡（1:1 跟手），松手时才把过渡打开 ——
   * 于是它从手指松开的地方「弹」到目标格，而不是先归位再跳一次。
   */
  /** 按住多久算「拿起来」；这之前手指挪过 DRAG_CANCEL_PX 就当是在滑页面，取消长按 */
  const LONG_PRESS_MS = 260;
  const DRAG_CANCEL_PX = 8;
  const pressTimerRef = useRef<number | null>(null);
  const pressStartRef = useRef<{ key: string; pointerId: number; x: number } | null>(null);
  const draggingRef = useRef(false);
  const navBoxRef = useRef<{ left: number; width: number } | null>(null);
  const slotRef = useRef<{ key: string; x: number; w: number }[]>([]);
  const suppressClickRef = useRef(false);
  const [dragging, setDragging] = useState(false);
  const [dragX, setDragX] = useState<number | null>(null);
  const [liftedKey, setLiftedKey] = useState<string | null>(null);

  /** 量一次「栏」和「每一项」的位置：拖动期间它们不会变，量一次就够 */
  const measureSlots = () => {
    const nav = bottomNavRef.current;
    if (!nav) return false;
    const navBox = nav.getBoundingClientRect();
    navBoxRef.current = { left: navBox.left, width: navBox.width };
    slotRef.current = NAV_ITEMS.map((item) => {
      const box = navItemRefs.current[item.key]?.getBoundingClientRect();
      return { key: item.key, x: (box?.left ?? navBox.left) - navBox.left, w: box?.width ?? 0 };
    });
    return true;
  };

  const clearPressTimer = () => {
    if (pressTimerRef.current !== null) {
      window.clearTimeout(pressTimerRef.current);
      pressTimerRef.current = null;
    }
  };

  /** 手指落在哪一项上（贴到栏外时按栏边算，边上那项照样选得到） */
  const slotAt = (clientX: number) => {
    const navBox = navBoxRef.current;
    if (!navBox) return null;
    const x = Math.max(navBox.left, Math.min(navBox.left + navBox.width, clientX)) - navBox.left;
    return slotRef.current.find((slot) => x >= slot.x && x < slot.x + slot.w) ?? null;
  };

  const handleNavPointerDown =
    (key: string) => (ev: React.PointerEvent<HTMLButtonElement>) => {
      if (!mobile || ev.button !== 0) return;
      suppressClickRef.current = false;
      pressStartRef.current = { key, pointerId: ev.pointerId, x: ev.clientX };
      clearPressTimer();
      pressTimerRef.current = window.setTimeout(() => {
        pressTimerRef.current = null;
        const start = pressStartRef.current;
        const nav = bottomNavRef.current;
        if (!start || !nav || !measureSlots()) return;
        const slot = slotRef.current.find((s) => s.key === activeTab);
        draggingRef.current = true;
        setDragging(true);
        setDragX(navPill?.x ?? slot?.x ?? 0);
        setLiftedKey(start.key);
        try {
          nav.setPointerCapture(start.pointerId);
        } catch {
          /* 指针已经不在活动状态，忽略 */
        }
        try {
          if ("vibrate" in navigator) navigator.vibrate(10);
        } catch {
          /* 有的浏览器不给震动，静默跳过 */
        }
      }, LONG_PRESS_MS);
    };

  const handleNavPointerMove = (ev: React.PointerEvent<HTMLElement>) => {
    const start = pressStartRef.current;
    if (!start) return;
    if (!draggingRef.current) {
      if (Math.abs(ev.clientX - start.x) > DRAG_CANCEL_PX) {
        clearPressTimer();
        pressStartRef.current = null;
      }
      return;
    }
    const navBox = navBoxRef.current;
    const slot = slotRef.current.find((s) => s.key === activeTab);
    if (!navBox || !slot) return;
    // 胶囊中心跟着手指，但不许滑出栏外
    const x = Math.max(0, Math.min(navBox.width - slot.w, ev.clientX - navBox.left - slot.w / 2));
    setDragX((prev) => (prev !== null && Math.abs(prev - x) < 1 ? prev : x));
    setLiftedKey(slotAt(ev.clientX)?.key ?? start.key);
  };

  const handleNavPointerUp = (ev: React.PointerEvent<HTMLElement>) => {
    clearPressTimer();
    const start = pressStartRef.current;
    pressStartRef.current = null;
    if (!draggingRef.current) return; // 普通短按：交给 onClick
    const target = slotAt(ev.clientX)?.key ?? start?.key ?? activeTab;
    draggingRef.current = false;
    try {
      bottomNavRef.current?.releasePointerCapture(ev.pointerId);
    } catch {
      /* 没捕获成功过，忽略 */
    }
    // 先把高光挪到目标格的坐标，再打开过渡 —— 它就从手指松开的地方弹过去
    const slot = slotRef.current.find((s) => s.key === target);
    if (slot) setNavPill({ x: slot.x, w: slot.w });
    setDragging(false);
    setDragX(null);
    setLiftedKey(null);
    suppressClickRef.current = true; // 拖完可能还会补一个 click，别让它再切一次
    if (target !== activeTab) handleNavClick(target);
  };

  const handleNavPointerCancel = () => {
    clearPressTimer();
    pressStartRef.current = null;
    if (!draggingRef.current) return;
    draggingRef.current = false;
    setDragging(false);
    setDragX(null);
    setLiftedKey(null);
  };

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

  /**
   * 下滑收栏 / 上滑放栏。
   * - 只在手机上做：电脑端顶栏是流内的一条，滑走会在顶上留一块空白。
   * - 顶部 HIDE_AFTER 之内永远不收：刚进页面还在看开头时，顶上那两条就是导航。
   * - 位移要累计超过 STEP 才认方向：手指微抖、滚到头的橡皮筋回弹都不会让栏子忽隐忽现。
   * - 切路由后 SUPPRESS 毫秒内不认：切换时会把内容滚回上次的位置，
   *   那一下位移不是用户滑的，别因此把栏子收走。
   */
  useEffect(() => {
    if (!mobile) {
      setChromeHidden(false);
      return;
    }
    const el = contentRef.current;
    if (!el) return;
    const HIDE_AFTER = 72;
    const STEP = 6;
    const SUPPRESS = 500;
    let raf = 0;
    let last = el.scrollTop;
    const until = performance.now() + SUPPRESS;
    const onScroll = () => {
      if (raf) return;
      raf = requestAnimationFrame(() => {
        raf = 0;
        const top = el.scrollTop;
        if (performance.now() < until) {
          last = top;
          return;
        }
        if (top <= HIDE_AFTER) {
          last = top;
          setChromeHidden(false);
          return;
        }
        const delta = top - last;
        if (delta > STEP) {
          last = top;
          setChromeHidden(true);
        } else if (delta < -STEP) {
          last = top;
          setChromeHidden(false);
        }
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
        <Header className={`${styles.header} ${chromeHidden ? styles.headerHidden : ""}`}>
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
        <nav
          ref={bottomNavRef}
          className={`${styles.bottomNav} ${chromeHidden ? styles.bottomNavHidden : ""}`}
          aria-label="主导航"
          onPointerMove={handleNavPointerMove}
          onPointerUp={handleNavPointerUp}
          onPointerCancel={handleNavPointerCancel}
          onContextMenu={(ev) => ev.preventDefault()}
        >
          {/* 选中高光：单独一条滑块，位置由上面的 useLayoutEffect 量出来，
              换 Tab 时它会从旧位置滑到新位置（带弹簧），而不是瞬间跳过去。
              长按拖动时它 1:1 跟手（inline transition:none），松手再交给 CSS 弹到目标格；
              玻璃的质感在内层 .navPillGlass 上，两层各管一个 transform、互不干扰 */}
          {navPill && (
            <span
              className={`${styles.navPill} ${dragging ? styles.navPillDragging : ""}`}
              aria-hidden="true"
              style={{
                transform: `translateX(${(dragging && dragX !== null ? dragX : navPill.x).toFixed(1)}px)`,
                width: navPill.w,
                transition: dragging ? "none" : undefined,
              }}
            >
              <span className={styles.navPillGlass} />
            </span>
          )}
          {NAV_ITEMS.map((item) => {
            const active = item.key === activeTab;
            const lifted = liftedKey === item.key;
            return (
              <button
                key={item.key}
                ref={(el) => {
                  navItemRefs.current[item.key] = el;
                }}
                type="button"
                className={`${styles.bottomNavItem} ${active ? styles.bottomNavItemActive : ""} ${
                  lifted ? styles.bottomNavItemLifted : ""
                }`}
                onPointerDown={handleNavPointerDown(item.key)}
                onClick={() => {
                  // 长按拖动收尾时浏览器可能补一个 click，吃掉它，别切两次
                  if (suppressClickRef.current) {
                    suppressClickRef.current = false;
                    return;
                  }
                  handleNavClick(item.key);
                }}
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
