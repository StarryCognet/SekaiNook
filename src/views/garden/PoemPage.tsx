import { useState } from 'react';
import { Card, Button, message } from 'antd';
import { BookOutlined, CheckOutlined } from '@ant-design/icons';
import { gardenTokens } from '../../theme/gardenTokens';
import styles from './PoemPage.module.css';

/** 古诗数据 */
const POEMS = [
  { id: 'jingyesi', title: '静夜思', author: '李白', text: '床前明月光，疑是地上霜。举头望明月，低头思故乡。' },
  { id: 'chunxiao', title: '春晓', author: '孟浩然', text: '春眠不觉晓，处处闻啼鸟。夜来风雨声，花落知多少。' },
  { id: 'chizhou', title: '池上', author: '白居易', text: '小娃撑小艇，偷采白莲回。不解藏踪迹，浮萍一道开。' },
  { id: 'xiaochi', title: '小池', author: '杨万里', text: '泉眼无声惜细流，树阴照水爱晴柔。小荷才露尖尖角，早有蜻蜓立上头。' },
];

/** 古诗背诵页面 */
export default function PoemPage() {
  const [done, setDone] = useState<Record<string, boolean>>({});

  const handleRecite = (id: string, title: string) => {
    setDone((prev) => ({ ...prev, [id]: true }));
    message.success(`《${title}》背诵成功！+10 阳光`);
  };

  return (
    <div className={styles.poem}>
      <div className={styles.sectionTitle}>今日古诗</div>
      <div className={styles.poemList}>
        {POEMS.map((poem) => (
          <Card
            key={poem.id}
            className={`${styles.poemCard} ${done[poem.id] ? styles.poemDone : ''}`}
            variant="borderless"
          >
            <div className={styles.poemHeader}>
              <div className={styles.poemTitle}>
                <BookOutlined style={{ color: gardenTokens.colors.primary }} />
                《{poem.title}》
              </div>
              <div className={styles.poemAuthor}>{poem.author}</div>
            </div>
            <div className={styles.poemText}>{poem.text}</div>
            <Button
              type="primary"
              size="small"
              className={styles.reciteBtn}
              style={{
                background: done[poem.id] ? gardenTokens.colors.success : gardenTokens.colors.primary,
                borderColor: done[poem.id] ? gardenTokens.colors.success : gardenTokens.colors.primary,
              }}
              icon={done[poem.id] ? <CheckOutlined /> : <BookOutlined />}
              onClick={() => handleRecite(poem.id, poem.title)}
              disabled={done[poem.id]}
            >
              {done[poem.id] ? '已背诵' : '背诵打卡'}
            </Button>
          </Card>
        ))}
      </div>
    </div>
  );
}