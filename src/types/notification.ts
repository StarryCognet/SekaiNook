/**
 * 通知收件箱类型（对应 D1 的 notifications 表，见 migrations/0003_notifications.sql）。
 *
 * 没有账号体系，就用两格信箱：家长一格、小孩一格。
 */

/** 收件人：家长 / 小孩 */
export type NotifyAudience = 'parent' | 'child';

/** 通知类型（服务端写入时决定，前端只用于挑图标与颜色） */
export type NotifyType =
  | 'checkin_pending'
  | 'approved'
  | 'rejected'
  | 'resubmitted'
  | 'recorded'
  | 'payout';

/** 一条通知 */
export interface NotificationRecord {
  id: string;
  audience: NotifyAudience;
  type: NotifyType | string;
  title: string;
  body?: string | null;
  /** 点击后跳转的路径，如 /family */
  link?: string | null;
  status: 'unread' | 'read';
  created_at: string;
  read_at?: string | null;
}

/** 接口返回：一页通知 + 该格信箱的未读数 */
export interface NotificationBox {
  items: NotificationRecord[];
  unreadCount: number;
  /** false = 后端通知表还没迁移好（此时前端按空信箱显示，不报错） */
  ready: boolean;
}
