import { createClient } from '@supabase/supabase-js';
import { localDb } from './localDb';
import { WEEKLY_PLAN_TEMPLATE } from '../config/familyRules';
import { getCurrentWeekLabel } from '../utils/week';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

/** 判断是否为占位符（未真正配置） */
const isPlaceholder = (url: string | undefined) =>
  !url || url.includes('your-project') || url.includes('your-anon');

/** 是否已配置 Supabase（未配置或为占位符则回退本地数据库） */
export const isSupabaseConfigured = Boolean(
  supabaseUrl && supabaseAnonKey && !isPlaceholder(supabaseUrl) && !isPlaceholder(supabaseAnonKey)
);

/**
 * 全局数据库客户端。
 * - 已配置 Supabase：使用云端数据库
 * - 未配置：回退到 localStorage 本地数据库（开箱即用）
 *
 * 类型标注为宽松的数据库客户端（适配层），兼容两种实现的 from() 用法。
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const supabase: any = isSupabaseConfigured
  ? createClient(supabaseUrl, supabaseAnonKey)
  : localDb;

/** 本地数据库模式下，初始化本周学习计划（幂等） */
let localPlanInitPromise: Promise<void> | null = null;

export async function ensureLocalWeeklyPlans(): Promise<void> {
  if (isSupabaseConfigured) return;
  const weekLabel = getCurrentWeekLabel();

  // 防止并发重复初始化（React StrictMode 会双调用 useEffect）
  if (localPlanInitPromise) return localPlanInitPromise;

  localPlanInitPromise = (async () => {
    const raw = localStorage.getItem('sekainook_db_weekly_plans');
    const rows: Array<{ week_label: string }> = raw ? JSON.parse(raw) : [];
    if (rows.some((r) => r.week_label === weekLabel)) return;

    // 通过 localDb 的 insert 写入，确保自动生成 id
    for (const tpl of WEEKLY_PLAN_TEMPLATE) {
      await localDb.from('weekly_plans').insert({
        subject: tpl.subject,
        task_name: tpl.task_name,
        target: tpl.target,
        current: 0,
        week_label: weekLabel,
      });
    }
  })();

  return localPlanInitPromise;
}