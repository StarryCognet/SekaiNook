import { Button, Card, Progress, message } from 'antd';
import { CheckOutlined, ReadOutlined } from '@ant-design/icons';
import { GARDEN_CHINESE_PRACTICES } from '../../config/garden';
import { todayKey, useGardenStore } from '../../store/useGardenStore';
import { useThemePalette } from '../../store/useThemeStore';
import styles from './ChinesePage.module.css';

/** 语文练习页面：每次打卡计一次花园任务完成并持久化 */
export default function ChinesePage() {
  const { chineseSteps, chineseDate, completeChineseStep } = useGardenStore();
  // 进度条 / 按钮等 CSS 变量到不了的地方，用当前主题调色板
  const palette = useThemePalette();
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
                  <ReadOutlined className={styles.previewTitleIcon} />
                  {item.title}
                </div>
                {done && <CheckOutlined className={styles.previewDoneIcon} />}
              </div>
              <div className={styles.previewDesc}>{item.desc}</div>
              <div className={styles.previewProgress}>
                <Progress
                  percent={percent}
                  size="small"
                  strokeColor={done ? palette.success : palette.primary}
                />
              </div>
              <Button
                type="primary"
                className={styles.previewBtn}
                style={{
                  background: done ? palette.success : palette.primary,
                  borderColor: done ? palette.success : palette.primary,
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
