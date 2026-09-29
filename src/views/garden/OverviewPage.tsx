import { Card, Progress } from 'antd';
import { SunOutlined, FireOutlined, TrophyOutlined } from '@ant-design/icons';
import { useGardenStore } from '../../store/useGardenStore';
import { useThemePalette } from '../../store/useThemeStore';
import styles from './OverviewPage.module.css';

/** 学习总览页面 */
export default function OverviewPage() {
  const { balance, tasks, completedCount, streakDays, badges } = useGardenStore();
  // 进度条等 antd 属性拿不到 CSS 变量，颜色从当前主题调色板取
  const palette = useThemePalette();
  const total = tasks.length;
  const percent = total > 0 ? Math.round((completedCount / total) * 100) : 0;
  const earnedBadges = badges.filter((b) => b.earned).length;

  return (
    <div className={styles.overview}>
      {/* 数据卡片 */}
      <div className={styles.statGrid}>
        <Card className={styles.statCard} variant="borderless">
          <div className={`${styles.statIcon} ${styles.statIconWarm}`}>
            <SunOutlined />
          </div>
          <div className={styles.statInfo}>
            <div className={styles.statLabel}>阳光余额</div>
            <div className={`num ${styles.statValue}`}>{balance}</div>
          </div>
        </Card>
        <Card className={styles.statCard} variant="borderless">
          <div className={`${styles.statIcon} ${styles.statIconBrand}`}>
            <FireOutlined />
          </div>
          <div className={styles.statInfo}>
            <div className={styles.statLabel}>连续学习</div>
            <div className={`num ${styles.statValue}`}>{streakDays} 天</div>
          </div>
        </Card>
        <Card className={styles.statCard} variant="borderless">
          <div className={`${styles.statIcon} ${styles.statIconSuccess}`}>
            <TrophyOutlined />
          </div>
          <div className={styles.statInfo}>
            <div className={styles.statLabel}>已获勋章</div>
            <div className={`num ${styles.statValue}`}>{earnedBadges}</div>
          </div>
        </Card>
      </div>

      {/* 今日进度 */}
      <Card className={styles.progressCard} variant="borderless">
        <div className={styles.progressTitle}>今日学习进度</div>
        <Progress
          percent={percent}
          strokeColor={palette.primary}
          trailColor="var(--color-surface-soft)"
          format={() => `${completedCount}/${total} 个任务`}
        />
      </Card>

      {/* 学习建议 */}
      <Card className={styles.tipCard} variant="borderless">
        <div className={styles.tipTitle}>今日小贴士</div>
        <div className={styles.tipText}>
          完成所有任务可以获得 <span className={`num ${styles.tipNum}`}>{total * 10}</span> 阳光积分，
          坚持学习还能解锁更多勋章哦！
        </div>
      </Card>
    </div>
  );
}
