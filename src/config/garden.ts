import type { GardenTask, Badge } from '../types/garden';

/** 今日任务列表（示例） */
export const GARDEN_TASKS: GardenTask[] = [
  { id: 'poem', name: '背一首古诗', duration: 10, description: '背诵并理解一首古诗', reward: 10, icon: 'book', done: false },
  { id: 'chinese', name: '语文预习 15 分钟', duration: 15, description: '预习明天要学的课文', reward: 15, icon: 'read', done: false },
  { id: 'math', name: '数学预习 15 分钟', duration: 15, description: '预习数学新章节', reward: 15, icon: 'calc', done: false },
  { id: 'reading', name: '课外阅读 20 分钟', duration: 20, description: '阅读课外书籍', reward: 20, icon: 'book-open', done: false },
  { id: 'writing', name: '练字 10 分钟', duration: 10, description: '认真练习书写', reward: 10, icon: 'pen', done: false },
  { id: 'eyes', name: '休息眼睛 5 分钟', duration: 5, description: '远眺放松眼睛', reward: 5, icon: 'eye', done: false },
  { id: 'sport', name: '运动 20 分钟', duration: 20, description: '户外活动或锻炼', reward: 20, icon: 'sport', done: false },
  { id: 'chore', name: '做一件家务', duration: 15, description: '帮助家人做家务', reward: 15, icon: 'home', done: false },
];

/** 勋章列表（初始均为未获得，达成条件后由 useGardenStore 解锁） */
export const GARDEN_BADGES: Badge[] = [
  { id: 'sunrise', name: '第一缕阳光', description: '完成第一个任务', icon: 'sun', earned: false },
  { id: 'gardener', name: '小园丁', description: '累计完成 10 个任务', icon: 'flower', earned: false },
  { id: 'streak3', name: '坚持 3 天', description: '连续学习 3 天', icon: 'calendar', earned: false },
  { id: 'week_champ', name: '一周冠军', description: '连续学习 7 天', icon: 'trophy', earned: false },
  { id: 'poet', name: '小诗人', description: '背诵 10 首古诗', icon: 'feather', earned: false },
  { id: 'plant_warrior', name: '植物战士', description: '照顾花园植物 7 天', icon: 'leaf', earned: false },
  { id: 'sun_rich', name: '阳光富翁', description: '累计获得 500 阳光', icon: 'coin', earned: false },
];

/** 古诗 */
export interface GardenPoem {
  id: string;
  title: string;
  author: string;
  /** 全文 */
  text: string;
  /** 背会后获得的阳光积分 */
  reward: number;
}

/** 古诗列表：累计背会 10 首可解锁「小诗人」勋章 */
export const GARDEN_POEMS: GardenPoem[] = [
  { id: 'jingyesi', title: '静夜思', author: '李白', text: '床前明月光，疑是地上霜。举头望明月，低头思故乡。', reward: 10 },
  { id: 'chunxiao', title: '春晓', author: '孟浩然', text: '春眠不觉晓，处处闻啼鸟。夜来风雨声，花落知多少。', reward: 10 },
  { id: 'chizhou', title: '池上', author: '白居易', text: '小娃撑小艇，偷采白莲回。不解藏踪迹，浮萍一道开。', reward: 10 },
  { id: 'xiaochi', title: '小池', author: '杨万里', text: '泉眼无声惜细流，树阴照水爱晴柔。小荷才露尖尖角，早有蜻蜓立上头。', reward: 10 },
  { id: 'yonge', title: '咏鹅', author: '骆宾王', text: '鹅，鹅，鹅，曲项向天歌。白毛浮绿水，红掌拨清波。', reward: 10 },
  { id: 'minnong', title: '悯农', author: '李绅', text: '锄禾日当午，汗滴禾下土。谁知盘中餐，粒粒皆辛苦。', reward: 10 },
  { id: 'dengguanquelou', title: '登鹳雀楼', author: '王之涣', text: '白日依山尽，黄河入海流。欲穷千里目，更上一层楼。', reward: 10 },
  { id: 'wanglushanpubu', title: '望庐山瀑布', author: '李白', text: '日照香炉生紫烟，遥看瀑布挂前川。飞流直下三千尺，疑是银河落九天。', reward: 10 },
  { id: 'jiangxue', title: '江雪', author: '柳宗元', text: '千山鸟飞绝，万径人踪灭。孤舟蓑笠翁，独钓寒江雪。', reward: 10 },
  { id: 'zengwanglun', title: '赠汪伦', author: '李白', text: '李白乘舟将欲行，忽闻岸上踏歌声。桃花潭水深千尺，不及汪伦送我情。', reward: 10 },
  { id: 'xunyinzhe', title: '寻隐者不遇', author: '贾岛', text: '松下问童子，言师采药去。只在此山中，云深不知处。', reward: 10 },
  { id: 'huichong', title: '惠崇春江晚景', author: '苏轼', text: '竹外桃花三两枝，春江水暖鸭先知。蒌蒿满地芦芽短，正是河豚欲上时。', reward: 10 },
];

/** 语文/汉字练习项 */
export interface GardenChinesePractice {
  id: string;
  title: string;
  desc: string;
  /** 打卡按钮文案（如「我写完了」） */
  actionLabel: string;
  /** 每次打卡获得的阳光积分 */
  reward: number;
  /** 每天可打卡次数（按自然日重置） */
  timesPerDay: number;
}

/** 语文练习列表：每打卡一次即计一次花园任务完成 */
export const GARDEN_CHINESE_PRACTICES: GardenChinesePractice[] = [
  { id: 'read_aloud', title: '课文朗读', desc: '朗读今天学的课文，读给家人听', actionLabel: '我读完了', reward: 5, timesPerDay: 3 },
  { id: 'new_words', title: '生字认读', desc: '认读本课生字，每个字读两遍并组词', actionLabel: '我认读完了', reward: 5, timesPerDay: 2 },
  { id: 'write_words', title: '生字书写', desc: '在田字格里认真书写本课生字', actionLabel: '我写完了', reward: 10, timesPerDay: 1 },
];

/** 商城物品分类 */
export type GardenShopCategory = 'avatar' | 'title' | 'decor';

/** 分类中文名 */
export const GARDEN_SHOP_CATEGORY_LABELS: Record<GardenShopCategory, string> = {
  avatar: '头像框',
  title: '称号',
  decor: '花园装饰',
};

/** 商城物品 */
export interface GardenShopItem {
  id: string;
  name: string;
  /** 兑换所需阳光积分 */
  cost: number;
  /** 图标 key（见 components/garden/GardenIcon） */
  icon: string;
  desc: string;
  category: GardenShopCategory;
}

/** 阳光商城商品：一次性拥有，不可重复兑换 */
export const GARDEN_SHOP_ITEMS: GardenShopItem[] = [
  { id: 'avatar_sun', name: '阳光头像框', cost: 60, icon: 'sun', desc: '把头像装进金色阳光里', category: 'avatar' },
  { id: 'avatar_star', name: '星星头像框', cost: 80, icon: 'star', desc: '闪闪发光的星星围着你的头像', category: 'avatar' },
  { id: 'title_poet', name: '称号・小诗人', cost: 100, icon: 'feather', desc: '名字旁边挂上「小诗人」', category: 'title' },
  { id: 'title_gardener', name: '称号・小园丁', cost: 120, icon: 'flower', desc: '名字旁边挂上「小园丁」', category: 'title' },
  { id: 'decor_rainbow', name: '装饰・彩虹花架', cost: 150, icon: 'flower', desc: '花园里多一架七色花', category: 'decor' },
  { id: 'decor_lantern', name: '装饰・星星灯串', cost: 200, icon: 'star', desc: '夜里给花园挂上小灯', category: 'decor' },
];

/** 累计型勋章的进度目标（id -> 目标值） */
export const GARDEN_BADGE_TARGETS: Record<string, number> = {
  poet: 10,
  plant_warrior: 7,
};

/** 儿童工作台 8 个菜单 */
export const GARDEN_MENUS = [
  { key: 'overview', label: '学习总览', icon: 'dashboard' },
  { key: 'tasks', label: '今日任务', icon: 'check' },
  { key: 'poem', label: '古诗背诵', icon: 'book' },
  { key: 'chinese', label: '语文预习', icon: 'read' },
  { key: 'garden', label: '阳光花园', icon: 'flower' },
  { key: 'shop', label: '阳光商城', icon: 'shop' },
  { key: 'rewards', label: '我的奖励', icon: 'trophy' },
  { key: 'records', label: '学习记录', icon: 'history' },
];