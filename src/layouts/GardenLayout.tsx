import { lazy, Suspense, useEffect } from 'react';
import { Progress } from 'antd';
import { SunOutlined, FireOutlined } from '@ant-design/icons';
import { GARDEN_MENUS } from '../config/garden';
import { useGardenStore } from '../store/useGardenStore';
import { getGardenIcon } from '../components/garden/GardenIcon';
import { useThemePalette } from '../store/useThemeStore';
import { PageLoading } from '../components/StateViews';
import { useViewState } from '../utils/useViewState';
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
  // 花园里选的是哪个子页也要跨页面切换保留（切去「家庭」再回来还停在原处）
  const [active, setActive] = useViewState('garden.activeMenu', 'tasks');
  // 花园状态：任务是「今日任务」，跨天自动重置（见 store 里的 tasksDate）
  const { balance, tasks, completedCount, streakDays, init } = useGardenStore();
  // 主题色（antd 属性拿不到 CSS 变量，只能从主题取）
  const palette = useThemePalette();

  // 初始化状态
  useEffect(() => {
    init();
  }, [init]);

  const totalTasks = tasks.length;
  const percent = totalTasks > 0 ? Math.round((completedCount / totalTasks) * 100) : 0;
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
            onClick={() => setActive(menu.key)}
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
            <span className={styles.userAvatar}>小</span>
            <span>小朋友</span>
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