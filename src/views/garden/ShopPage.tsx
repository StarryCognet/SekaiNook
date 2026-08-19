import { Card, Button, message } from 'antd';
import { SunOutlined, PlayCircleOutlined, GiftOutlined, StarOutlined } from '@ant-design/icons';
import { useGardenStore } from '../../store/useGardenStore';
import { gardenTokens } from '../../theme/gardenTokens';
import styles from './ShopPage.module.css';

/** 商城商品 */
const ITEMS = [
  { id: 'cartoon', name: '看动画 30 分钟', cost: 30, icon: 'play', desc: '兑换 30 分钟动画时间' },
  { id: 'game', name: '玩游戏 20 分钟', cost: 40, icon: 'star', desc: '兑换 20 分钟游戏时间' },
  { id: 'gift', name: '小礼物', cost: 100, icon: 'gift', desc: '兑换一份小礼物' },
];

/** 阳光商城页面 */
export default function ShopPage() {
  const { balance } = useGardenStore();

  const handleExchange = (name: string, cost: number) => {
    if (balance < cost) {
      message.warning('阳光积分不足，快去完成任务吧！');
      return;
    }
    message.success(`兑换成功！${name}`);
  };

  return (
    <div className={styles.shop}>
      <div className={styles.sectionTitle}>阳光商城</div>

      {/* 余额提示 */}
      <Card className={styles.balanceCard} variant="borderless">
        <SunOutlined style={{ color: gardenTokens.colors.sun, fontSize: 22 }} />
        <span className={styles.balanceText}>我的阳光余额</span>
        <span className={`num ${styles.balanceNum}`}>{balance}</span>
        <span className={styles.balanceLabel}>阳光</span>
      </Card>

      {/* 商品列表 */}
      <div className={styles.itemGrid}>
        {ITEMS.map((item) => (
          <Card key={item.id} className={styles.itemCard} variant="borderless">
            <div className={styles.itemIcon}>
              {item.icon === 'play' ? (
                <PlayCircleOutlined />
              ) : item.icon === 'gift' ? (
                <GiftOutlined />
              ) : (
                <StarOutlined />
              )}
            </div>
            <div className={styles.itemName}>{item.name}</div>
            <div className={styles.itemDesc}>{item.desc}</div>
            <div className={styles.itemCost}>
              <SunOutlined style={{ color: gardenTokens.colors.sun }} />
              <span className={`num ${styles.itemCostNum}`}>{item.cost}</span>
              <span className={styles.itemCostLabel}>阳光</span>
            </div>
            <Button
              type="primary"
              size="small"
              className={styles.exchangeBtn}
              style={{
                background: gardenTokens.colors.primary,
                borderColor: gardenTokens.colors.primary,
              }}
              onClick={() => handleExchange(item.name, item.cost)}
            >
              兑换
            </Button>
          </Card>
        ))}
      </div>
    </div>
  );
}