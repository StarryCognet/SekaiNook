import { useEffect, useState } from 'react';
import { Progress, Button } from 'antd';
import { SunOutlined, FireOutlined, ReloadOutlined } from '@ant-design/icons';
import { GARDEN_MENUS } from '../config/garden';
import { useGardenStore } from '../store/useGardenStore';
import { getGardenIcon } from '../components/garden/GardenIcon';
import { gardenTokens } from '../theme/gardenTokens';
import OverviewPage from '../views/garden/OverviewPage';
import TasksPage from '../views/garden/TasksPage';
import PoemPage from '../views/garden/PoemPage';
import ChinesePage from '../views/garden/ChinesePage';
import GardenPage from '../views/garden/GardenPage';
import ShopPage from '../views/garden/ShopPage';
import RewardsPage from '../views/garden/RewardsPage';
import RecordsPage from '../views/garden/RecordsPage';
import styles from './GardenLayout.module.css';

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
  const [active, setActive] = useState('tasks');
  const { balance, tasks, completedCount, streakDays, init, resetTasks } = useGardenStore();

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
            <SunOutlined style={{ color: gardenTokens.colors.sun }} />
            <span className={styles.balanceNum}>{balance}</span>
            <span className={styles.balanceLabel}>阳光</span>
          </div>

          <div className={styles.progressChip}>
            <span className={styles.progressLabel}>今日进度</span>
            <Progress
              percent={percent}
              size="small"
              strokeColor={gardenTokens.colors.success}
              className={styles.progressBar}
            />
            <span className={styles.progressText}>{completedCount}/{totalTasks}</span>
          </div>

          <div className={styles.streakChip}>
            <FireOutlined style={{ color: gardenTokens.colors.sun }} />
            <span className={styles.streakNum}>{streakDays}</span>
            <span className={styles.streakLabel}>天</span>
          </div>

          <Button
            size="small"
            icon={<ReloadOutlined />}
            className={styles.resetBtn}
            onClick={resetTasks}
          >
            重置
          </Button>
        </div>
      </div>

      {/* ===== 内容区 ===== */}
      <div className="page-transition">
        <ActivePage />
      </div>
    </div>
  );
}