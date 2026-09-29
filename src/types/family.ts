/** 任务类型：赚钱（earning，正数）/ 花钱与罚款（spending，负数） */
export type TaskType = 'earning' | 'spending';

/** 流水审批状态：待审批 / 已审批入账 / 已驳回 */
export type LedgerStatus = 'pending' | 'approved' | 'rejected';

/** 任务配置（来自 config/familyRules.ts 的唯一数据源） */
export interface TaskConfig {
  id: string;
  name: string;
  type: TaskType;
  value: number;
  unit: string;
  description?: string;
  /**
   * 每天最多可提交次数（缺省不限）。
   * 用于防止连点/重复打卡；小孩端已提交的待审批记录同样计入次数。
   */
  dailyLimit?: number;
  /**
   * 允许打卡的时间窗（24 小时制 "HH:mm"，闭区间，不支持跨零点；缺省不限）。
   * 例如「按时睡觉」只在 19:00-21:30 内可打卡。
   */
  window?: { start: string; end: string };
}

/** 积分流水记录 */
export interface LedgerRecord {
  id: string;
  task_id: string;
  task_name: string;
  type: TaskType;
  amount: number;
  created_at: string;
  /** 任务备注（可选） */
  note?: string | null;
  /** 任务图片 URL（可选，来自 R2） */
  image_url?: string | null;
  /** 审批状态（缺省视为已入账，兼容存量数据） */
  status?: LedgerStatus;
  /**
   * 历史遗留字段：曾经用于多孩子家庭按成员分开记账，多成员功能已下线（界面上不再出现）。
   * D1 的 member 列仍在（老数据不回改），新写入的记录该字段为空。
   */
  member?: string | null;
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