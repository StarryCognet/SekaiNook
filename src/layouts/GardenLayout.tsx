import { lazy, Suspense, useEffect } from 'react';
import { useSearchParams } from 'react-router-dom';
import { Progress } from 'antd';
import { SunOutlined, FireOutlined } from '@ant-design/icons';
import {
  GARDEN_DEFAULT_MENU,
  GARDEN_MENUS,
  GARDEN_MENU_PARAM,
  isGardenMenuKey,
} from '../config/garden';
import { useGardenStore } from '../store/useGardenStore';
import { getGardenIcon } from '../components/garden/GardenIcon';
import { useThemePalette } from '../store/useThemeStore';
import { useKidName } from '../store/useSettingsStore';
import { PageLoading } from '../components/StateViews';
import { setViewState, useViewState } from '../utils/useViewState';
import styles from './GardenLayout.module.css';

/** 8 个子页面按需加载：切到哪个菜单才拉哪个页面的 chunk */
const OverviewPage = lazy(() => import('../views/garden/OverviewPage'));
const TasksPage = lazy(() => import('../views/garden/TasksPage'));
const PoemPage = lazy(() => import('../views/garden/PoemPage'));
const ChinesePage = lazy(() => import('../views/garden/ChinesePage'));
const GardenPage = lazy(() => import('../views/garden/GardenPage'));
const ShopPage = lazy(() => import('../views/garden/ShopPage'));
const RewardsPage = lazy(() => import('../views/garden/RewardsPage'));
const RecordsPage = lazy(() => import('../views/garden/RecordsPage'));

/** 子页面映射 */
const PAGE_MAP: Record<string, React.ComponentType> = {
  overview: OverviewPage,
  tasks: TasksPage,
  poem: PoemPage,
  chinese: ChinesePage,
  garden: GardenPage,
  shop: ShopPage,
  rewards: RewardsPage,
  records: RecordsPage,
};

/** 阳光花园・学习乐园 布局 */
export default function GardenLayout() {
  /**
   * 花园里选的是哪个子页，唯一真相是地址栏：`/garden?tab=poem`。
   * 以前存在 useViewState 里（纯 state，不进历史）有两个病：
   *   ① 点几次菜单后按系统返回键，直接退出花园（历史里根本没有菜单这一层）；
   *   ② 那个缓存 key 没有身份维度 —— 小孩停在「愿望单」，家长进花园也落在「愿望单」。
   * 改成查询参数后这两点一起没了：菜单是 URL 的一部分，天然能回退、天然各人各份。
   */
  const [searchParams, setSearchParams] = useSearchParams();
  const tabParam = searchParams.get(GARDEN_MENU_PARAM);
  // 不带参数、或参数是未知值（旧链接 / 手改地址栏）都落默认菜单，绝不渲染空白
  const active = isGardenMenuKey(tabParam) ? tabParam : GARDEN_DEFAULT_MENU;

  /**
   * 兼容首页那几个「去花园的某个子页」的快捷入口（KidHome 先把菜单写进 garden.activeMenu，
   * 再导航到 /garden）。这里只把它当作一次性的深链意图：搬进 URL 之后立刻清掉，
   * 此后只剩 URL 说话 —— 于是它也不会再像以前那样跨身份留给下一个进花园的人。
   * TODO(KidHome.tsx)：改成 navigate(`/garden?tab=${menu}`) 之后，这段兼容连同上面那个 key 都能删掉。
   */
  const [menuIntent] = useViewState<string>('garden.activeMenu', '');
  const intent =
    !searchParams.has(GARDEN_MENU_PARAM) && isGardenMenuKey(menuIntent) ? menuIntent : '';

  useEffect(() => {
    if (!intent) return;
    // 用 replace：首页那次导航留下的历史就是这一条，别再多塞一条空历史进去
    setSearchParams({ [GARDEN_MENU_PARAM]: intent }, { replace: true });
    setViewState('garden.activeMenu', '');
  }, [intent, setSearchParams]);

  /** 点菜单：push 一条新的 ?tab=（不能 replace，否则系统返回键还是直接退出花园） */
  const selectMenu = (key: string) => {
    // 点的就是当前菜单：不制造一条原样的历史，免得返回键按一下像没反应
    if (key === active) return;
    const next = new URLSearchParams(searchParams);
    next.set(GARDEN_MENU_PARAM, key);
    setSearchParams(next, { replace: false });
  };

  // 花园状态：任务是「今日任务」，跨天自动重置（见 store 里的 tasksDate）
  const { balance, tasks, completedCount, streakDays, init } = useGardenStore();
  // 主题色（antd 属性拿不到 CSS 变量，只能从主题取）
  const palette = useThemePalette();
  // 孩子的昵称（设置里能改）—— 页面上别写死「小朋友」
  const kidName = useKidName();

  // 初始化状态
  useEffect(() => {
    init();
  }, [init]);

  const totalTasks = tasks.length;
  // 分子分母同口径（都是今日任务数）之后再夹一次 100：老存档里被撑大的数字也不会溢出
  const percent =
    totalTasks > 0 ? Math.min(100, Math.max(0, Math.round((completedCount / totalTasks) * 100))) : 0;
  const today = new Date().toLocaleDateString('zh-CN', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    weekday: 'long',
  });

  const ActivePage = PAGE_MAP[active] ?? TasksPage;

  return (
    <div className={styles.garden}>
      {/* ===== 顶部品牌区 ===== */}
      <div className={styles.brand}>
        <div className={styles.brandDecor} />
        <div className={styles.logo}>
          <span className={styles.logoText}>阳光</span>
        </div>
        <div className={styles.brandText}>
          <div className={styles.title}>阳光花园・学习乐园</div>
          <div className={styles.subtitle}>快乐学习，茁壮成长</div>
        </div>
        <div className={styles.brandSun}>
          <SunOutlined />
        </div>
      </div>

      {/* ===== 8 个菜单导航 ===== */}
      <nav className={styles.nav}>
        {GARDEN_MENUS.map((menu) => (
          <button
            key={menu.key}
            className={`${styles.navItem} ${active === menu.key ? styles.navItemActive : ''}`}
            onClick={() => selectMenu(menu.key)}
          >
            <span className={styles.navIcon}>{getGardenIcon(menu.icon)}</span>
            <span className={styles.navLabel}>{menu.label}</span>
          </button>
        ))}
      </nav>

      {/* ===== 顶部信息栏 ===== */}
      <div className={styles.topbar}>
        <div className={styles.topbarLeft}>
          <div className={styles.pageTitle}>
            {GARDEN_MENUS.find((m) => m.key === active)?.label ?? '今日任务'}
          </div>
          <div className={styles.date}>{today}</div>
        </div>

        <div className={styles.topbarRight}>
          <div className={styles.userChip}>
            <span className={styles.userAvatar}>{kidName.slice(0, 1)}</span>
            <span>{kidName}</span>
          </div>

          <div className={styles.balanceChip}>
            <SunOutlined style={{ color: palette.warning }} />
            <span className={styles.balanceNum}>{balance}</span>
            <span className={styles.balanceLabel}>阳光</span>
          </div>

          <div className={styles.progressChip}>
            <span className={styles.progressLabel}>今日进度</span>
            <Progress
              percent={percent}
              size="small"
              strokeColor={palette.primary}
              trailColor="var(--color-surface-soft)"
              className={styles.progressBar}
            />
            <span className={styles.progressText}>{completedCount}/{totalTasks}</span>
          </div>

          <div className={styles.streakChip}>
            <FireOutlined style={{ color: palette.warning }} />
            <span className={styles.streakNum}>{streakDays}</span>
            <span className={styles.streakLabel}>天</span>
          </div>
        </div>
      </div>

      {/* ===== 内容区（每个花园页面各自按需加载，加载中显示统一 Loading） ===== */}
      <div className="page-transition">
        <Suspense fallback={<PageLoading />}>
          <ActivePage />
        </Suspense>
      </div>
    </div>
  );
}