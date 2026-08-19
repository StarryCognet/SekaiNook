import type { TaskConfig } from '../types/family';

/**
 * 赚钱/花钱/罚款任务规则 —— 唯一数据源。
 * 所有任务名、积分值、单位均从此处读取，禁止在组件中硬编码。
 */
export const TASK_RULES: TaskConfig[] = [
  // ===== 赚钱区（earning，正数）=====
  { id: 'clean_room', name: '整理房间', type: 'earning', value: 10, unit: '元' },
  { id: 'wash_dishes', name: '洗碗', type: 'earning', value: 5, unit: '元' },
  { id: 'do_laundry', name: '洗衣服', type: 'earning', value: 15, unit: '元' },
  { id: 'take_out_trash', name: '倒垃圾', type: 'earning', value: 5, unit: '元' },
  { id: 'finish_homework', name: '按时完成作业', type: 'earning', value: 20, unit: '元' },
  { id: 'read_book', name: '课外阅读30分钟', type: 'earning', value: 10, unit: '元' },
  { id: 'sleep_on_time', name: '按时睡觉', type: 'earning', value: 10, unit: '元' },

  // ===== 花钱区（spending，负数）=====
  { id: 'ipad_time', name: '看iPad 30分钟', type: 'spending', value: -10, unit: '积分' },
  { id: 'phone_time', name: '玩手机 30分钟', type: 'spending', value: -10, unit: '积分' },

  // ===== 罚款区（spending，负数）=====
  {
    id: 'eye_penalty',
    name: '视力下降1度',
    type: 'spending',
    value: -100,
    unit: '积分',
    description: '保护眼睛',
  },
  {
    id: 'sleep_penalty',
    name: '未按时作息(晚于21:00)',
    type: 'spending',
    value: -20,
    unit: '积分',
  },
  { id: 'homework_incomplete', name: '作业未完成', type: 'spending', value: -50, unit: '积分' },
];

/** 按类型筛选任务 */
export function getTasksByType(type: 'earning' | 'spending'): TaskConfig[] {
  return TASK_RULES.filter((t) => t.type === type);
}

/** 每周学习计划模板（subject -> 任务列表） */
export const WEEKLY_PLAN_TEMPLATE: Array<{
  subject: string;
  task_name: string;
  target: number;
}> = [
  // 英语
  { subject: '英语', task_name: '单词背诵', target: 50 },
  { subject: '英语', task_name: '小作文', target: 1 },
  // 语文
  { subject: '语文', task_name: '课文预习', target: 2 },
  { subject: '语文', task_name: '课外阅读', target: 3 },
  // 数学
  { subject: '数学', task_name: '口算练习', target: 5 },
  { subject: '数学', task_name: '错题订正', target: 10 },
  // 日常
  { subject: '日常', task_name: '9:00前睡觉', target: 7 },
  { subject: '日常', task_name: '7:00起床', target: 7 },
];