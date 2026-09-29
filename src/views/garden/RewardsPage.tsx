import { Progress } from 'antd';
import { TrophyOutlined } from '@ant-design/icons';
import { GARDEN_BADGE_TARGETS } from '../../config/garden';
import { useGardenStore } from '../../store/useGardenStore';
import { getGardenIcon } from '../../components/garden/GardenIcon';
import { useThemePalette } from '../../store/useThemeStore';
import styles from './RewardsPage.module.css';

/** 累计型勋章的进度（未解锁也可见） */
interface BadgeProgress {
  current: number;
  target: number;
  text: string;
}

/** 我的奖励页面：成就面板 + 勋章墙 */
export default function RewardsPage() {
  const { badges, poemCount, gardenCareDays } = useGardenStore();
  const palette = useThemePalette();

  const earnedCount = badges.filter((b) => b.earned).length;
  const totalCount = badges.length;
  const percent = totalCount > 0 ? Math.round((earnedCount / totalCount) * 100) : 0;

  // 「小诗人」「植物战士」的进度：未解锁也能看到还差多少
  const progressOf: Record<string, BadgeProgress | undefined> = {
    poet: {
      current: poemCount,
      target: GARDEN_BADGE_TARGETS.poet,
      text: `背诵 ${poemCount}/${GARDEN_BADGE_TARGETS.poet} 首`,
    },
    plant_warrior: {
      current: gardenCareDays,
      target: GARDEN_BADGE_TARGETS.plant_warrior,
      text: `照顾花园 ${gardenCareDays}/${GARDEN_BADGE_TARGETS.plant_warrior} 天`,
    },
  };

  return (
    <div className={styles.rewards}>
      {/* 顶部成就面板（暖色提示块） */}
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
          {badges.map((badge) => {
            const progress = progressOf[badge.id];
            return (
              <div
                key={badge.id}
                className={`${styles.badgeCard} ${badge.earned ? styles.badgeEarned : styles.badgeLocked}`}
              >
                <div className={styles.badgeIcon}>{getGardenIcon(badge.icon)}</div>
                <div className={styles.badgeName}>{badge.name}</div>
                <div className={styles.badgeDesc}>{badge.description}</div>
                {progress && (
                  <div className={styles.badgeProgress}>
                    <Progress
                      percent={
                        progress.target > 0
                          ? Math.min(100, Math.round((progress.current / progress.target) * 100))
                          : 0
                      }
                      size="small"
                      showInfo={false}
                      strokeColor={badge.earned ? palette.success : palette.primary}
                    />
                    <div
                      className={`${styles.badgeProgressText} ${
                        badge.earned ? styles.badgeProgressTextEarned : ''
                      }`}
                    >
                      {progress.text}
                    </div>
                  </div>
                )}
                {badge.earned ? (
                  <div className={styles.badgeStatus}>已获得</div>
                ) : (
                  <div className={styles.badgeStatusLocked}>未获得</div>
                )}
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
