import { Button, Card, message } from 'antd';
import { SunOutlined } from '@ant-design/icons';
import {
  GARDEN_SHOP_CATEGORY_LABELS,
  GARDEN_SHOP_ITEMS,
  toShopItemShortName,
  type GardenShopCategory,
} from '../../config/garden';
import { useGardenStore } from '../../store/useGardenStore';
import { getGardenIcon } from '../../components/garden/GardenIcon';
import styles from './ShopPage.module.css';

/** 商品分类展示顺序 */
const CATEGORY_ORDER: GardenShopCategory[] = ['avatar', 'title', 'decor'];

/** 「戴上 / 挂上」的按钮文案：头像框与称号是戴，装饰是挂（都用孩子听得懂的话） */
const EQUIP_LABELS: Record<GardenShopCategory, string> = {
  avatar: '戴上',
  title: '戴上',
  decor: '挂上',
};

/** 阳光商城页面：用阳光积分兑换；买到的东西可以戴上 / 挂上，正在用的显示「使用中」 */
export default function ShopPage() {
  const {
    balance,
    ownedItems,
    buyItem,
    equippedAvatar,
    equippedTitle,
    equippedDecor,
    equipItem,
    unequipItem,
  } = useGardenStore();

  // 顶部「现在戴着」那一行：把 id 翻回商城物品（名字去掉「称号・」这类前缀）
  const avatarItem = GARDEN_SHOP_ITEMS.find((item) => item.id === equippedAvatar);
  const titleItem = GARDEN_SHOP_ITEMS.find((item) => item.id === equippedTitle);
  const decorItems = GARDEN_SHOP_ITEMS.filter(
    (item) => item.category === 'decor' && equippedDecor.includes(item.id)
  );

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

  /** 这件东西现在是不是正用着 */
  const isInUse = (category: GardenShopCategory, id: string) =>
    category === 'avatar'
      ? equippedAvatar === id
      : category === 'title'
        ? equippedTitle === id
        : equippedDecor.includes(id);

  /** 「戴上 / 挂上」与「取下」共用一个按钮：正在用的再点一次就是取下来 */
  const handleToggle = (id: string, name: string, category: GardenShopCategory) => {
    const shortName = toShopItemShortName(name);
    if (isInUse(category, id)) {
      unequipItem(id);
      message.info(
        category === 'decor' ? `「${shortName}」已经从花园里摘下来啦` : `「${shortName}」已经取下来啦`
      );
      return;
    }
    const result = equipItem(id);
    if (result === 'owned') {
      message.warning('还没有这件东西，先去兑换吧');
      return;
    }
    if (result === 'unknown') {
      message.error('没有找到这个物品，请刷新后再试');
      return;
    }
    message.success(
      category === 'decor' ? `「${shortName}」挂到花园里啦` : `「${shortName}」戴上啦`
    );
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

      {/* 现在戴着 / 挂着的：买过的东西一眼能看见，不再只有一句「已拥有」 */}
      <Card className={styles.wearingCard} variant="borderless">
        <div className={styles.wearingTitle}>现在戴着 / 挂着的</div>
        <div className={styles.wearingRow}>
          <span className={styles.wearingLabel}>头像框</span>
          {avatarItem ? (
            <span className={styles.wearingValue}>
              <span className={styles.wearingIcon}>{getGardenIcon(avatarItem.icon)}</span>
              {toShopItemShortName(avatarItem.name)}
            </span>
          ) : (
            <span className={styles.wearingEmpty}>还没戴</span>
          )}
        </div>
        <div className={styles.wearingRow}>
          <span className={styles.wearingLabel}>称号</span>
          {titleItem ? (
            <span className={styles.wearingValue}>
              <span className={styles.wearingIcon}>{getGardenIcon(titleItem.icon)}</span>
              {toShopItemShortName(titleItem.name)}
            </span>
          ) : (
            <span className={styles.wearingEmpty}>还没挂</span>
          )}
        </div>
        <div className={styles.wearingRow}>
          <span className={styles.wearingLabel}>花园里</span>
          {decorItems.length > 0 ? (
            decorItems.map((item) => (
              <span key={item.id} className={styles.wearingValue}>
                <span className={styles.wearingIcon}>{getGardenIcon(item.icon)}</span>
                {toShopItemShortName(item.name)}
              </span>
            ))
          ) : (
            <span className={styles.wearingEmpty}>还没有装饰</span>
          )}
        </div>
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
                const inUse = isInUse(item.category, item.id);
                return (
                  <Card
                    key={item.id}
                    className={`${styles.itemCard} ${
                      inUse
                        ? styles.itemInUse
                        : owned
                          ? styles.itemOwned
                          : affordable
                            ? ''
                            : styles.itemLocked
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
                        inUse || owned
                          ? styles.itemStatusOwned
                          : affordable
                            ? styles.itemStatusReady
                            : styles.itemStatusLocked
                      }`}
                    >
                      {inUse ? '正在用' : owned ? '已拥有' : affordable ? '可以兑换' : '阳光不足'}
                    </div>
                    {owned ? (
                      <Button
                        type={inUse ? 'default' : 'primary'}
                        className={styles.exchangeBtn}
                        onClick={() => handleToggle(item.id, item.name, item.category)}
                      >
                        {inUse ? '取下' : EQUIP_LABELS[item.category]}
                      </Button>
                    ) : (
                      <Button
                        type={affordable ? 'primary' : 'dashed'}
                        className={styles.exchangeBtn}
                        onClick={() => handleExchange(item.id, item.name, item.cost)}
                      >
                        兑换
                      </Button>
                    )}
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
