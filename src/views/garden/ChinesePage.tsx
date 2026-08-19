import { Card, Progress, Button, message } from 'antd';
import { ReadOutlined, CheckOutlined } from '@ant-design/icons';
import { useState } from 'react';
import { gardenTokens } from '../../theme/gardenTokens';
import styles from './ChinesePage.module.css';

/** 预习内容 */
const PREVIEW_ITEMS = [
  { id: 'lesson1', title: '第一课 课文预习', desc: '朗读课文 3 遍，圈出生字', target: 3 },
  { id: 'lesson2', title: '第二课 课文预习', desc: '朗读课文 3 遍，圈出生字', target: 3 },
  { id: 'words', title: '生字词练习', desc: '书写本课生字词', target: 2 },
];

/** 语文预习页面 */
export default function ChinesePage() {
  const [progress, setProgress] = useState<Record<string, number>>({
    lesson1: 0,
    lesson2: 0,
    words: 0,
  });

  const handleAdd = (id: string, target: number) => {
    setProgress((prev) => {
      const next = Math.min((prev[id] ?? 0) + 1, target);
      if (next === target) {
        message.success('预习完成！+15 阳光');
      }
      return { ...prev, [id]: next };
    });
  };

  return (
    <div className={styles.chinese}>
      <div className={styles.sectionTitle}>语文预习</div>
      <div className={styles.previewList}>
        {PREVIEW_ITEMS.map((item) => {
          const current = progress[item.id] ?? 0;
          const done = current >= item.target;
          const percent = Math.min(100, Math.round((current / item.target) * 100));
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
                size="small"
                className={styles.previewBtn}
                style={{
                  background: done ? gardenTokens.colors.success : gardenTokens.colors.primary,
                  borderColor: done ? gardenTokens.colors.success : gardenTokens.colors.primary,
                }}
                onClick={() => handleAdd(item.id, item.target)}
                disabled={done}
              >
                {done ? '已完成' : `打卡 (${current}/${item.target})`}
              </Button>
            </Card>
          );
        })}
      </div>
    </div>
  );
}