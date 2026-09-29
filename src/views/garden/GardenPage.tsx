import { Button, Card, Progress, message } from 'antd';
import { EnvironmentOutlined, SmileOutlined, SunOutlined } from '@ant-design/icons';
import { GARDEN_BADGE_TARGETS } from '../../config/garden';
import { todayKey, useGardenStore } from '../../store/useGardenStore';
import { useThemePalette } from '../../store/useThemeStore';
import styles from './GardenPage.module.css';

/** 花园植物 */
const PLANTS = [
  { id: 'sunflower', name: '向日葵', icon: 'flower', desc: '阳光越足，长得越高' },
  { id: 'rose', name: '小玫瑰', icon: 'flower', desc: '需要细心照顾' },
  { id: 'cactus', name: '仙人掌', icon: 'leaf', desc: '坚强的小植物' },
];

/** 阳光花园页面 */
export default function GardenPage() {
  // 进度条这类 antd 属性色到不了 CSS 变量，从当前主题调色板取
  const palette = useThemePalette();
  const { tasks, completedCount, gardenCareDays, lastCareDate, careForGarden } = useGardenStore();
  // 花园成长度基于今日完成任务数
  // 成长度 = 今天任务的完成比例。以前写死 `completedCount * 10`，而任务只有 8 个，
  // 于是全做完也只有 80%，孩子会觉得「明明做完了却没满」
  const growth = tasks.length > 0 ? Math.round((completedCount / tasks.length) * 100) : 0;

  const today = todayKey();
  const caredToday = lastCareDate === today;
  const careTarget = GARDEN_BADGE_TARGETS.plant_warrior;
  const carePercent = careTarget > 0 ? Math.min(100, Math.round((gardenCareDays / careTarget) * 100)) : 0;

  const handleCare = () => {
    if (careForGarden()) {
      message.success('照顾成功！植物们精神多啦');
      return;
    }
    message.info('今天的花园已经照顾过啦，明天再来吧');
  };

  return (
    <div className={styles.garden}>
      <div className={styles.sectionTitle}>我的阳光花园</div>

      {/* 花园状态 */}
      <Card className={styles.gardenStatus} variant="borderless">
        <div className={styles.gardenSun}>
          <SunOutlined />
        </div>
        <div className={styles.gardenInfo}>
          <div className={styles.gardenTitle}>花园成长度</div>
          <Progress
            percent={growth}
            strokeColor={palette.success}
            format={() => `${growth}%`}
          />
          <div className={styles.gardenDesc}>完成更多任务，让花园更茂盛！</div>
        </div>
      </Card>

      {/* 照顾花园：累计自然日，满 7 天解锁「植物战士」 */}
      <Card className={styles.gardenStatus} variant="borderless">
        <div className={styles.gardenSun}>
          <EnvironmentOutlined />
        </div>
        <div className={styles.gardenInfo}>
          <div className={styles.gardenTitle}>照顾花园 · 植物战士</div>
          <Progress
            percent={carePercent}
            strokeColor={palette.primary}
            format={() => `${gardenCareDays}/${careTarget} 天`}
          />
          <div className={styles.gardenDesc}>
            {caredToday
              ? '今天已经照顾过植物啦，明天记得再来～'
              : `给植物浇浇水，坚持 ${careTarget} 天就能解锁「植物战士」勋章`}
          </div>
          <Button
            type="primary"
            className={styles.careBtn}
            icon={<EnvironmentOutlined />}
            disabled={caredToday}
            onClick={handleCare}
          >
            {caredToday ? '今天已照顾' : '浇浇水'}
          </Button>
        </div>
      </Card>

      {/* 植物列表 */}
      <div className={styles.plantGrid}>
        {PLANTS.map((plant) => (
          <Card key={plant.id} className={styles.plantCard} variant="borderless">
            <div className={styles.plantIcon}>
              {plant.icon === 'flower' ? <SmileOutlined /> : <EnvironmentOutlined />}
            </div>
            <div className={styles.plantName}>{plant.name}</div>
            <div className={styles.plantDesc}>{plant.desc}</div>
            <Button
              className={`${styles.careBtn} ${styles.plantCareBtn}`}
              disabled={caredToday}
              onClick={handleCare}
            >
              {caredToday ? '今天已照顾' : '浇浇水'}
            </Button>
          </Card>
        ))}
      </div>
    </div>
  );
}
