import { Button, Card, message } from 'antd';
import { SunOutlined } from '@ant-design/icons';
import {
  GARDEN_SHOP_CATEGORY_LABELS,
  GARDEN_SHOP_ITEMS,
  type GardenShopCategory,
} from '../../config/garden';
import { useGardenStore } from '../../store/useGardenStore';
import { getGardenIcon } from '../../components/garden/GardenIcon';
import { gardenTokens } from '../../theme/gardenTokens';
import styles from './ShopPage.module.css';

/** 触控目标最小高度（安卓手机上的小朋友友好）：由令牌间距组合得到 */
const TOUCH_HEIGHT = gardenTokens.spacing.xl + gardenTokens.spacing.md;

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
        <SunOutlined style={{ color: gardenTokens.colors.sun, fontSize: 22 }} />
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
            <div
              className={styles.categoryTitle}
              style={{ color: gardenTokens.colors.text, marginBottom: gardenTokens.spacing.sm }}
            >
              {GARDEN_SHOP_CATEGORY_LABELS[category]}
            </div>
            <div className={styles.itemGrid}>
              {items.map((item) => {
                const owned = ownedItems.includes(item.id);
                const affordable = balance >= item.cost;
                return (
                  <Card
                    key={item.id}
                    className={`${styles.itemCard} ${owned ? styles.itemOwned : ''}`}
                    variant="borderless"
                    style={{
                      borderRadius: gardenTokens.radius.lg,
                      border: owned
                        ? `2px solid ${gardenTokens.colors.success}`
                        : affordable
                          ? undefined
                          : `2px dashed ${gardenTokens.colors.gray}`,
                      background: owned ? gardenTokens.colors.successBg : undefined,
                    }}
                  >
                    <div className={styles.itemIcon}>{getGardenIcon(item.icon)}</div>
                    <div className={styles.itemName}>{item.name}</div>
                    <div className={styles.itemDesc}>{item.desc}</div>
                    <div className={styles.itemCost}>
                      <SunOutlined
                        style={{ color: affordable ? gardenTokens.colors.sun : gardenTokens.colors.gray }}
                      />
                      <span
                        className={`num ${styles.itemCostNum}`}
                        style={{ color: affordable ? gardenTokens.colors.sun : gardenTokens.colors.gray }}
                      >
                        {item.cost}
                      </span>
                      <span className={styles.itemCostLabel}>阳光</span>
                    </div>
                    <div
                      className={styles.itemStatus}
                      style={{
                        marginBottom: gardenTokens.spacing.sm,
                        color: owned
                          ? gardenTokens.colors.success
                          : affordable
                            ? gardenTokens.colors.textSecondary
                            : gardenTokens.colors.gray,
                      }}
                    >
                      {owned ? '已拥有' : affordable ? '可以兑换' : '阳光不足'}
                    </div>
                    <Button
                      type={owned ? 'default' : affordable ? 'primary' : 'dashed'}
                      className={styles.exchangeBtn}
                      style={{
                        minHeight: TOUCH_HEIGHT,
                        ...(owned || !affordable
                          ? {}
                          : {
                              background: gardenTokens.colors.primary,
                              borderColor: gardenTokens.colors.primary,
                            }),
                      }}
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
