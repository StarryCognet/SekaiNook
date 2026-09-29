import { Button, Card, Progress, message } from 'antd';
import { BookOutlined, CheckOutlined } from '@ant-design/icons';
import { GARDEN_BADGE_TARGETS, GARDEN_POEMS } from '../../config/garden';
import { todayKey, useGardenStore } from '../../store/useGardenStore';
import { gardenTokens } from '../../theme/gardenTokens';
import styles from './PoemPage.module.css';

/** 触控目标最小高度（安卓手机上的小朋友友好）：由令牌间距组合得到 */
const TOUCH_HEIGHT = gardenTokens.spacing.xl + gardenTokens.spacing.md;

/** 古诗背诵页面 */
export default function PoemPage() {
  const { poemCount, todayPoemIds, poemDate, recitePoem } = useGardenStore();
  const today = todayKey();
  // 跨天后今日打卡记录自动失效
  const doneToday = poemDate === today ? todayPoemIds : [];
  const poetTarget = GARDEN_BADGE_TARGETS.poet;
  const poetPercent = poetTarget > 0 ? Math.min(100, Math.round((poemCount / poetTarget) * 100)) : 0;
  const poetRemain = Math.max(0, poetTarget - poemCount);

  const handleRecite = (id: string, title: string, reward: number) => {
    if (!recitePoem(id)) {
      message.info(`《${title}》今天已经背过啦，明天再来复习吧`);
      return;
    }
    message.success(`《${title}》背诵成功！+${reward} 阳光`);
  };

  return (
    <div className={styles.poem}>
      {/* 小诗人进度 */}
      <Card
        className={styles.poemProgressCard}
        variant="borderless"
        style={{
          borderRadius: gardenTokens.radius.lg,
          background: gardenTokens.colors.primaryBg,
        }}
      >
        <div
          className={styles.poemProgressText}
          style={{ color: gardenTokens.colors.text, marginBottom: gardenTokens.spacing.sm }}
        >
          累计背会{' '}
          <span className="num" style={{ color: gardenTokens.colors.primary }}>
            {poemCount}
          </span>{' '}
          首
          {poetRemain > 0 ? `，还差 ${poetRemain} 首解锁「小诗人」` : '，已经解锁「小诗人」啦'}
        </div>
        <Progress percent={poetPercent} size="small" strokeColor={gardenTokens.colors.primary} />
      </Card>

      <div className={styles.sectionTitle}>今日古诗</div>
      <div className={styles.poemList}>
        {GARDEN_POEMS.map((poem) => {
          const done = doneToday.includes(poem.id);
          return (
            <Card
              key={poem.id}
              className={`${styles.poemCard} ${done ? styles.poemDone : ''}`}
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
                className={styles.reciteBtn}
                style={{
                  background: done ? gardenTokens.colors.success : gardenTokens.colors.primary,
                  borderColor: done ? gardenTokens.colors.success : gardenTokens.colors.primary,
                  minHeight: TOUCH_HEIGHT,
                }}
                icon={done ? <CheckOutlined /> : <BookOutlined />}
                onClick={() => handleRecite(poem.id, poem.title, poem.reward)}
                disabled={done}
              >
                {done ? '今天已背会' : `我背会了 +${poem.reward}`}
              </Button>
            </Card>
          );
        })}
      </div>
    </div>
  );
}
