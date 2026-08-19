import dayjs from 'dayjs';
import isoWeek from 'dayjs/plugin/isoWeek';

dayjs.extend(isoWeek);

/**
 * 生成 ISO 周标签，格式：ISO年 + "-W" + 两位周数，例：2026-W34。
 * 与后端 SQL to_char(now(),'IYYY-"W"IW') 保持一致。
 */
export function getIsoWeekLabel(date: Date = new Date()): string {
  const d = dayjs(date);
  const year = d.isoWeekYear();
  const week = d.isoWeek();
  return `${year}-W${String(week).padStart(2, '0')}`;
}

/** 获取当前周标签 */
export function getCurrentWeekLabel(): string {
  return getIsoWeekLabel();
}