import { http } from './http';
import { WEEKLY_PLAN_TEMPLATE } from '../config/familyRules';
import type { WeeklyPlan } from '../types/family';

/** 查询某周的学习计划 */
export async function fetchWeeklyPlans(weekLabel: string): Promise<WeeklyPlan[]> {
  return http.get<WeeklyPlan[]>(`/api/plans?week=${encodeURIComponent(weekLabel)}`);
}

/**
 * 幂等初始化某周的学习计划：该周已有数据则原样返回，否则按模板写入后返回。
 * 返回该周完整计划，调用方无需再单独查询。
 */
export async function ensureWeeklyPlans(weekLabel: string): Promise<WeeklyPlan[]> {
  return http.post<WeeklyPlan[]>('/api/plans', {
    week_label: weekLabel,
    items: WEEKLY_PLAN_TEMPLATE,
  });
}

/** 更新某条学习计划的当前进度 */
export async function updateWeeklyPlan(planId: string, current: number): Promise<boolean> {
  await http.patch<{ ok: true }>(`/api/plans/${encodeURIComponent(planId)}`, { current });
  return true;
}
