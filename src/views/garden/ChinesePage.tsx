import { Button, Card, Progress, message } from 'antd';
import { CheckOutlined, ReadOutlined } from '@ant-design/icons';
import { GARDEN_CHINESE_PRACTICES } from '../../config/garden';
import { todayKey, useGardenStore } from '../../store/useGardenStore';
import { gardenTokens } from '../../theme/gardenTokens';
import styles from './ChinesePage.module.css';

/** 触控目标最小高度（安卓手机上的小朋友友好）：由令牌间距组合得到 */
const TOUCH_HEIGHT = gardenTokens.spacing.xl + gardenTokens.spacing.md;

/** 语文练习页面：每次打卡计一次花园任务完成并持久化 */
export default function ChinesePage() {
  const { chineseSteps, chineseDate, completeChineseStep } = useGardenStore();
  const today = todayKey();
  // 跨天后今日打卡次数自动归零
  const steps = chineseDate === today ? chineseSteps : {};

  const handlePractice = (id: string, title: string, reward: number, isLast: boolean) => {
    if (!completeChineseStep(id)) {
      message.info(`${title}今天已经练完啦，明天继续加油`);
      return;
    }
    message.success(isLast ? `${title}完成啦！+${reward} 阳光` : `打卡成功！+${reward} 阳光`);
  };

  return (
    <div className={styles.chinese}>
      <div className={styles.sectionTitle}>语文练习</div>
      <div className={styles.previewList}>
        {GARDEN_CHINESE_PRACTICES.map((item) => {
          const current = steps[item.id] ?? 0;
          const done = current >= item.timesPerDay;
          const percent = Math.min(100, Math.round((current / item.timesPerDay) * 100));
          return (
            <Card
              key={item.id}
              className={`${styles.previewCard} ${done ? styles.previewDone : ''}`}
              variant="borderless"
            >
              <div className={styles.previewHeader}>
                <div className={styles.previewTitle}>
                  <ReadOutlined style={{ color: gardenTokens.colors.primary }} />
                  {item.title}
                </div>
                {done && <CheckOutlined style={{ color: gardenTokens.colors.success }} />}
              </div>
              <div className={styles.previewDesc}>{item.desc}</div>
              <div className={styles.previewProgress}>
                <Progress
                  percent={percent}
                  size="small"
                  strokeColor={done ? gardenTokens.colors.success : gardenTokens.colors.primary}
                />
              </div>
              <Button
                type="primary"
                className={styles.previewBtn}
                style={{
                  background: done ? gardenTokens.colors.success : gardenTokens.colors.primary,
                  borderColor: done ? gardenTokens.colors.success : gardenTokens.colors.primary,
                  minHeight: TOUCH_HEIGHT,
                }}
                icon={done ? <CheckOutlined /> : undefined}
                onClick={() =>
                  handlePractice(item.id, item.title, item.reward, current + 1 >= item.timesPerDay)
                }
                disabled={done}
              >
                {done
                  ? '今天已完成'
                  : `${item.actionLabel} (${current}/${item.timesPerDay}) +${item.reward}`}
              </Button>
            </Card>
          );
        })}
      </div>
    </div>
  );
}
