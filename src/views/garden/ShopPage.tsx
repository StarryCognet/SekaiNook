import { Button, Card, message } from 'antd';
import { SunOutlined } from '@ant-design/icons';
import {
  GARDEN_SHOP_CATEGORY_LABELS,
  GARDEN_SHOP_ITEMS,
  type GardenShopCategory,
} from '../../config/garden';
import { useGardenStore } from '../../store/useGardenStore';
import { getGardenIcon } from '../../components/garden/GardenIcon';
import styles from './ShopPage.module.css';

/** 商品分类展示顺序 */
const CATEGORY_ORDER: GardenShopCategory[] = ['avatar', 'title', 'decor'];

/** 阳光商城页面：用阳光积分兑换，兑换后扣减余额并写入已拥有清单 */
export default function ShopPage() {
  const { balance, ownedItems, buyItem } = useGardenStore();

  const handleExchange = (id: string, name: string, cost: number) => {
    const result = buyItem(id);
    if (result === 'owned') {
      message.info(`已经拥有「${name}」啦，不用重复兑换`);
      return;
    }
    if (result === 'insufficient') {
      message.warning('阳光积分不足，快去完成任务攒阳光吧！');
      return;
    }
    if (result === 'unknown') {
      message.error('没有找到这个物品，请刷新后再试');
      return;
    }
    message.success(`兑换成功！「${name}」已拥有（-${cost} 阳光）`);
  };

  return (
    <div className={styles.shop}>
      <div className={styles.sectionTitle}>阳光商城</div>

      {/* 余额提示 */}
      <Card className={styles.balanceCard} variant="borderless">
        <SunOutlined className={styles.balanceIcon} />
        <span className={styles.balanceText}>我的阳光余额</span>
        <span className={`num ${styles.balanceNum}`}>{balance}</span>
        <span className={styles.balanceLabel}>阳光</span>
      </Card>

      {/* 商品列表（按分类展示） */}
      {CATEGORY_ORDER.map((category) => {
        const items = GARDEN_SHOP_ITEMS.filter((item) => item.category === category);
        if (items.length === 0) return null;
        return (
          <div key={category} className={styles.categoryBlock}>
            <div className={styles.categoryTitle}>{GARDEN_SHOP_CATEGORY_LABELS[category]}</div>
            <div className={styles.itemGrid}>
              {items.map((item) => {
                const owned = ownedItems.includes(item.id);
                const affordable = balance >= item.cost;
                return (
                  <Card
                    key={item.id}
                    className={`${styles.itemCard} ${
                      owned ? styles.itemOwned : affordable ? '' : styles.itemLocked
                    }`}
                    variant="borderless"
                  >
                    <div className={styles.itemIcon}>{getGardenIcon(item.icon)}</div>
                    <div className={styles.itemName}>{item.name}</div>
                    <div className={styles.itemDesc}>{item.desc}</div>
                    <div className={`${styles.itemCost} ${affordable ? '' : styles.itemCostLocked}`}>
                      <SunOutlined />
                      <span className={`num ${styles.itemCostNum}`}>{item.cost}</span>
                      <span className={styles.itemCostLabel}>阳光</span>
                    </div>
                    <div
                      className={`${styles.itemStatus} ${
                        owned
                          ? styles.itemStatusOwned
                          : affordable
                            ? styles.itemStatusReady
                            : styles.itemStatusLocked
                      }`}
                    >
                      {owned ? '已拥有' : affordable ? '可以兑换' : '阳光不足'}
                    </div>
                    <Button
                      type={owned ? 'default' : affordable ? 'primary' : 'dashed'}
                      className={styles.exchangeBtn}
                      disabled={owned}
                      onClick={() => handleExchange(item.id, item.name, item.cost)}
                    >
                      {owned ? '已拥有' : '兑换'}
                    </Button>
                  </Card>
                );
              })}
            </div>
          </div>
        );
      })}
    </div>
  );
}
