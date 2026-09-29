/**
 * 通知收件箱接口客户端。
 *
 * 通知没有「创建」接口：它们由服务端在记账 / 审批 / 结算处写入
 *（见 functions/_lib/notifications.ts），前端只读与标记已读。
 */

import { http } from './http';
import type { NotificationBox, NotifyAudience } from '../types/notification';

/** 读取某一格信箱的通知（按时间倒序）与未读数 */
export function fetchNotifications(
  audience: NotifyAudience,
  limit = 50
): Promise<NotificationBox> {
  return http.get<NotificationBox>(
    `/api/notifications?audience=${audience}&limit=${Math.max(1, Math.floor(limit))}`
  );
}

/** 标记一条通知为已读 */
export function markNotificationRead(id: string): Promise<{ ok: boolean }> {
  return http.patch<{ ok: boolean }>(`/api/notifications/${encodeURIComponent(id)}`, {
    status: 'read',
  });
}

/** 整格信箱一键已读 */
export function markAllNotificationsRead(
  audience: NotifyAudience
): Promise<{ ok: boolean; updated: number }> {
  return http.post<{ ok: boolean; updated: number }>('/api/notifications/read-all', { audience });
}
