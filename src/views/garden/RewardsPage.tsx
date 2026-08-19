import { TrophyOutlined } from '@ant-design/icons';
import { useGardenStore } from '../../store/useGardenStore';
import { getGardenIcon } from '../../components/garden/GardenIcon';
import styles from './RewardsPage.module.css';

/** 我的奖励页面：成就面板 + 勋章墙 */
export default function RewardsPage() {
  const { badges } = useGardenStore();

  const earnedCount = badges.filter((b) => b.earned).length;
  const totalCount = badges.length;
  const percent = totalCount > 0 ? Math.round((earnedCount / totalCount) * 100) : 0;

  return (
    <div className={styles.rewards}>
      {/* 顶部成就面板（淡黄色） */}
      <div className={styles.achievement}>
        <div className={styles.achievementIcon}>
          <TrophyOutlined />
        </div>
        <div className={styles.achievementInfo}>
          <div className={styles.achievementTitle}>花园小达人</div>
          <div className={styles.achievementDesc}>
            已获得 <span className={`num ${styles.achievementNum}`}>{earnedCount}</span> 枚勋章
          </div>
          <div className={styles.achievementBar}>
            <div className={styles.achievementBarFill} style={{ width: `${percent}%` }} />
          </div>
          <div className={styles.achievementProgress}>
            成就进度 <span className={`num ${styles.achievementNum}`}>{percent}%</span>
          </div>
        </div>
      </div>

      {/* 勋章墙 */}
      <div className={styles.badgeSection}>
        <div className={styles.sectionTitle}>我的勋章</div>
        <div className={styles.badgeGrid}>
          {badges.map((badge) => (
            <div
              key={badge.id}
              className={`${styles.badgeCard} ${badge.earned ? styles.badgeEarned : styles.badgeLocked}`}
            >
              <div className={styles.badgeIcon}>{getGardenIcon(badge.icon)}</div>
              <div className={styles.badgeName}>{badge.name}</div>
              <div className={styles.badgeDesc}>{badge.description}</div>
              {badge.earned ? (
                <div className={styles.badgeStatus}>已获得</div>
              ) : (
                <div className={styles.badgeStatusLocked}>未获得</div>
              )}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}