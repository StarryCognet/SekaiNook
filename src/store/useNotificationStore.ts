import { create } from 'zustand';
import {
  fetchNotifications,
  markAllNotificationsRead,
  markNotificationRead,
} from '../api/notifications';
import type { NotificationRecord, NotifyAudience } from '../types/notification';

/**
 * 通知收件箱状态。
 *
 * 与 useFamilyStore 的分工：家庭 store 管账（余额、流水、待审批），
 * 这里管「谁对谁做了什么」的消息。两者都会在轮询里刷新。
 *
 * 标记已读走乐观更新：先改本地（角标立刻变小），失败再拉一次真实数据兜底。
 */

const DEFAULT_LIMIT = 50;

interface NotificationState {
  /** 当前身份对应的信箱（未选身份时为 null） */
  audience: NotifyAudience | null;
  items: NotificationRecord[];
  /** 未读数（角标用；来自服务端计数，不受分页影响） */
  unreadCount: number;
  /** 首次加载中（下拉刷新式的静默刷新不算） */
  loading: boolean;
  /** false = 后端通知表尚未迁移好 */
  ready: boolean;
  error: string | null;
  /** 切换到某格信箱并加载（身份变化时调用） */
  load: (audience: NotifyAudience, limit?: number) => Promise<void>;
  /** 静默刷新（轮询用，不显示 loading，失败保留旧数据） */
  refresh: () => Promise<void>;
  /** 标记一条已读 */
  markRead: (id: string) => Promise<void>;
  /** 整格信箱一键已读 */
  markAllRead: () => Promise<void>;
}

export const useNotificationStore = create<NotificationState>((set, get) => {
  /** 当前已加载的分页大小（刷新时沿用） */
  let limit = DEFAULT_LIMIT;

  return {
    audience: null,
    items: [],
    unreadCount: 0,
    loading: false,
    ready: true,
    error: null,

    load: async (audience, nextLimit = DEFAULT_LIMIT) => {
      limit = nextLimit;
      const switching = get().audience !== audience;
      set({
        audience,
        loading: true,
        // 换身份时先清空，避免把上一格信箱的消息递给另一个人看
        ...(switching ? { items: [], unreadCount: 0, error: null } : {}),
      });

      try {
        const box = await fetchNotifications(audience, nextLimit);
        // 请求期间身份可能又变了，丢掉过期结果
        if (get().audience !== audience) return;
        set({
          items: box.items,
          unreadCount: box.unreadCount,
          ready: box.ready,
          loading: false,
          error: null,
        });
      } catch (e) {
        set({
          loading: false,
          error: e instanceof Error ? e.message : '通知加载失败',
        });
      }
    },

    refresh: async () => {
      const audience = get().audience;
      if (!audience) return;
      try {
        const box = await fetchNotifications(audience, limit);
        if (get().audience !== audience) return;
        set({
          items: box.items,
          unreadCount: box.unreadCount,
          ready: box.ready,
          error: null,
        });
      } catch {
        // 轮询失败不打扰用户：保留上一次的数据，等下一轮
      }
    },

    markRead: async (id) => {
      const target = get().items.find((item) => item.id === id);
      if (!target || target.status === 'read') return;

      const readAt = new Date().toISOString();
      set({
        items: get().items.map((item) =>
          item.id === id ? { ...item, status: 'read', read_at: readAt } : item
        ),
        unreadCount: Math.max(0, get().unreadCount - 1),
      });

      try {
        await markNotificationRead(id);
      } catch {
        await get().refresh();
      }
    },

    markAllRead: async () => {
      const { audience, items, unreadCount } = get();
      if (!audience || unreadCount === 0) return;

      const readAt = new Date().toISOString();
      set({
        items: items.map((item) =>
          item.status === 'unread' ? { ...item, status: 'read', read_at: readAt } : item
        ),
        unreadCount: 0,
      });

      try {
        await markAllNotificationsRead(audience);
      } catch {
        await get().refresh();
      }
    },
  };
});
