/**
 * 任务打卡规则：每日次数上限与时间窗。
 *
 * 从账本页里抽出来，让账本页与首页（妹妹版）用同一套判断 ——
 * 规则写在两处迟早会写歪（一边让打卡、一边说超限）。
 */

import type { LedgerRecord, TaskConfig } from '../types/family';

/** 当天该任务已提交次数（含待审批，不含被驳回；被驳回的不占名额） */
export function countTodaySubmissions(
  records: readonly LedgerRecord[],
  taskId: string,
  now: Date = new Date()
): number {
  const today = now.toDateString();
  return records.filter(
    (r) =>
      r.task_id === taskId &&
      r.status !== 'rejected' &&
      new Date(r.created_at).toDateString() === today
  ).length;
}

/** 任务能否打卡；不能时返回给用户看的提示文案 */
export function checkTask(
  task: TaskConfig,
  records: readonly LedgerRecord[],
  now: Date = new Date()
): string | null {
  if (task.window) {
    const [startH, startM] = task.window.start.split(':').map(Number);
    const [endH, endM] = task.window.end.split(':').map(Number);
    const minutes = now.getHours() * 60 + now.getMinutes();
    if (minutes < startH * 60 + startM || minutes > endH * 60 + endM) {
      return `「${task.name}」只能在 ${task.window.start}-${task.window.end} 之间打卡`;
    }
  }
  if (task.dailyLimit !== undefined && countTodaySubmissions(records, task.id, now) >= task.dailyLimit) {
    return task.dailyLimit === 1
      ? `「${task.name}」今天已经打过卡啦`
      : `「${task.name}」每天最多 ${task.dailyLimit} 次，今天用完啦`;
  }
  return null;
}

/** 是否已达今日上限（按钮置灰，避免重复打卡） */
export function isTaskDone(
  task: TaskConfig,
  records: readonly LedgerRecord[],
  now: Date = new Date()
): boolean {
  return task.dailyLimit !== undefined && countTodaySubmissions(records, task.id, now) >= task.dailyLimit;
}

/** 今日完成的任务数 / 有上限的任务总数（首页进度用；不限次数的任务不计入分母） */
export function todayProgress(
  tasks: readonly TaskConfig[],
  records: readonly LedgerRecord[],
  now: Date = new Date()
): { done: number; total: number; percent: number } {
  const limited = tasks.filter((task) => task.dailyLimit !== undefined);
  const total = limited.length;
  const done = limited.filter((task) => isTaskDone(task, records, now)).length;
  const percent = total === 0 ? 0 : Math.round((done / total) * 100);
  return { done, total, percent };
}
