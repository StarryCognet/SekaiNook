/** 任务类型：赚钱（earning，正数）/ 花钱与罚款（spending，负数） */
export type TaskType = 'earning' | 'spending';

/** 任务配置（来自 config/familyRules.ts 的唯一数据源） */
export interface TaskConfig {
  id: string;
  name: string;
  type: TaskType;
  value: number;
  unit: string;
  description?: string;
}

/** 积分流水记录 */
export interface LedgerRecord {
  id: string;
  task_id: string;
  task_name: string;
  type: TaskType;
  amount: number;
  created_at: string;
}

/** 每周学习计划 */
export interface WeeklyPlan {
  id: string;
  subject: string;
  task_name: string;
  target: number;
  current: number;
  week_label: string;
}