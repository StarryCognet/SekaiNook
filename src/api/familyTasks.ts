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

/**
 * 更新某条学习计划的当前进度，返回服务端**夹取后**的真实值。
 *
 * 服务端写入前会把 current 收敛到 [0, target]（functions/api/plans/[id].ts:47），
 * 所以调用方必须拿这个返回值回写本地 state —— 否则会出现「界面显示 60 / 目标 50、
 * 库里其实是 50」的错位，之后每次 +1 都继续错。
 */
export async function updateWeeklyPlan(planId: string, current: number): Promise<number> {
  const res = await http.patch<{ ok: boolean; current?: number }>(
    `/api/plans/${encodeURIComponent(planId)}`,
    { current }
  );
  // 老部署没回 current 时退回入参，至少不让界面变空
  return typeof res?.current === 'number' && Number.isFinite(res.current) ? res.current : current;
}
