/** 儿童学习任务 */
export interface GardenTask {
  id: string;
  name: string;
  /** 学习时长（分钟） */
  duration: number;
  /** 任务说明 */
  description: string;
  /** 阳光奖励积分 */
  reward: number;
  /** 图标 key（映射到图标组件） */
  icon: string;
  /** 是否已完成 */
  done: boolean;
  /** 完成时间 */
  completedAt?: string;
}

/** 勋章 */
export interface Badge {
  id: string;
  name: string;
  description: string;
  icon: string;
  /** 是否已获得 */
  earned: boolean;
}

/** 儿童工作台全局状态 */
export interface GardenState {
  /** 阳光积分余额 */
  balance: number;
  /** 今日任务 */
  tasks: GardenTask[];
  /** 勋章 */
  badges: Badge[];
  /** 连续学习天数 */
  streakDays: number;
  /**
   * 今日已完成的花园任务数（从 tasks 里 done 的条目派生，不会超过任务总数）。
   * 今日实际入账的阳光是另一个口径，见 useGardenStore 的 todayEarned。
   */
  completedCount: number;
}