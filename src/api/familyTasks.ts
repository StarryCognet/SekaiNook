import { supabase } from './supabaseClient';
import type { WeeklyPlan } from '../types/family';

/** 查询某周的学习计划 */
export async function fetchWeeklyPlans(weekLabel: string): Promise<WeeklyPlan[]> {
  const { data, error } = await supabase
    .from('weekly_plans')
    .select('*')
    .eq('week_label', weekLabel)
    .order('created_at', { ascending: true });
  if (error) throw error;
  return (data ?? []) as WeeklyPlan[];
}

/** 更新某条学习计划的当前进度 */
export async function updateWeeklyPlan(planId: string, current: number): Promise<boolean> {
  const { error } = await supabase
    .from('weekly_plans')
    .update({ current })
    .eq('id', planId);
  if (error) throw error;
  return true;
}