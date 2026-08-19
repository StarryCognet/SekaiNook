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

/** 勋章列表 */
export const GARDEN_BADGES: Badge[] = [
  { id: 'sunrise', name: '第一缕阳光', description: '完成第一个任务', icon: 'sun', earned: true },
  { id: 'gardener', name: '小园丁', description: '累计完成 10 个任务', icon: 'flower', earned: true },
  { id: 'streak3', name: '坚持 3 天', description: '连续学习 3 天', icon: 'calendar', earned: true },
  { id: 'week_champ', name: '一周冠军', description: '连续学习 7 天', icon: 'trophy', earned: false },
  { id: 'poet', name: '小诗人', description: '背诵 10 首古诗', icon: 'feather', earned: false },
  { id: 'plant_warrior', name: '植物战士', description: '照顾花园植物 7 天', icon: 'leaf', earned: false },
  { id: 'sun_rich', name: '阳光富翁', description: '累计获得 500 阳光', icon: 'coin', earned: false },
];

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