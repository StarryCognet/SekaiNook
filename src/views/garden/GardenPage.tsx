import { Card, Progress } from 'antd';
import { SmileOutlined, SunOutlined, EnvironmentOutlined } from '@ant-design/icons';
import { useGardenStore } from '../../store/useGardenStore';
import { gardenTokens } from '../../theme/gardenTokens';
import styles from './GardenPage.module.css';

/** 花园植物 */
const PLANTS = [
  { id: 'sunflower', name: '向日葵', icon: 'flower', desc: '阳光越足，长得越高' },
  { id: 'rose', name: '小玫瑰', icon: 'flower', desc: '需要细心照顾' },
  { id: 'cactus', name: '仙人掌', icon: 'leaf', desc: '坚强的小植物' },
];

/** 阳光花园页面 */
export default function GardenPage() {
  const { completedCount } = useGardenStore();
  // 花园成长度基于完成任务数
  const growth = Math.min(100, completedCount * 10);

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
            strokeColor={gardenTokens.colors.success}
            format={() => `${growth}%`}
          />
          <div className={styles.gardenDesc}>完成更多任务，让花园更茂盛！</div>
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
          </Card>
        ))}
      </div>
    </div>
  );
}