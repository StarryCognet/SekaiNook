import { useEffect, useState } from 'react';
import type { LedgerRecord } from '../../types/family';

/**
 * 首页专用的小工具：都是「把数据翻译成人话」的函数。
 *
 * 首页有实时时钟、问候语、21 点提醒，都需要一个会走的「现在」，
 * 所以这里提供一个 useNow：每分钟重算一次，避免为了一个钟点把整页重渲染得太勤。
 */
export function useNow(intervalMs = 60000): Date {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const timer = setInterval(() => setNow(new Date()), intervalMs);
    return () => clearInterval(timer);
  }, [intervalMs]);
  return now;
}

/** 问候语（按钟点分档，孩子半夜打开也不会说「早上好」） */
export function greetingText(now: Date): string {
  const hour = now.getHours();
  if (hour < 6) return '还没睡呀';
  if (hour < 11) return '早上好';
  if (hour < 14) return '中午好';
  if (hour < 18) return '下午好';
  return '晚上好';
}

const WEEK_TEXT = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];

/** 9月29日 星期一 */
export function dateText(now: Date): string {
  return `${now.getMonth() + 1}月${now.getDate()}日 ${WEEK_TEXT[now.getDay()]}`;
}

/** 14:32 */
export function clockText(date: Date): string {
  return `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
}

/** 本地日历天（不用 toISOString：那是 UTC，晚上 8 点后会把今天算成明天） */
function dayKey(date: Date): string {
  return `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()}`;
}

/** 今天的流水（records 本身按时间倒序，这里只筛不改序） */
export function todayRecords(records: readonly LedgerRecord[], now: Date): LedgerRecord[] {
  const today = dayKey(now);
  return records.filter((r) => dayKey(new Date(r.created_at)) === today);
}

/**
 * 滚动最近 N 天（含今天）的收支合计，只算已入账的。
 *
 * - `count`：区间内所有已入账流水条数（含消费、兑现）；
 * - `checkins`：其中真正「打卡 / 获得」的条数 —— 只数正数流水，
 *   消费罚款与现金兑现（payout 是 spending，金额为负）都不算打卡。
 *
 * 注意这里是**滚动 N 天**、不是自然周：文案必须照这个口径写（见 ParentHome 的概览卡）。
 */
export function recentSummary(
  records: readonly LedgerRecord[],
  days: number,
  now: Date
): { income: number; expense: number; net: number; count: number; checkins: number } {
  const from = new Date(now);
  from.setDate(from.getDate() - (days - 1));
  from.setHours(0, 0, 0, 0);

  let income = 0;
  let expense = 0;
  let count = 0;
  let checkins = 0;
  for (const r of records) {
    if (r.status && r.status !== 'approved') continue;
    const at = new Date(r.created_at);
    if (Number.isNaN(at.getTime()) || at < from) continue;
    if (r.amount > 0) {
      income += r.amount;
      checkins += 1;
    } else {
      expense += r.amount;
    }
    count += 1;
  }
  return { income, expense, net: income + expense, count, checkins };
}

/** 今天 14:32 / 昨天 09:05 / 9月20日 21:10 */
export function relativeTime(iso: string, now: Date): string {
  const at = new Date(iso);
  if (Number.isNaN(at.getTime())) return '';
  const time = clockText(at);
  const key = dayKey(at);
  if (key === dayKey(now)) return `今天 ${time}`;
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  if (key === dayKey(yesterday)) return `昨天 ${time}`;
  return `${at.getMonth() + 1}月${at.getDate()}日 ${time}`;
}
