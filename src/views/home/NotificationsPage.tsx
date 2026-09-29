import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button, Segmented, message } from 'antd';
import {
  BellOutlined,
  CheckCircleOutlined,
  ClockCircleOutlined,
  CloseCircleOutlined,
  EditOutlined,
  GiftOutlined,
  LeftOutlined,
  RedoOutlined,
} from '@ant-design/icons';
import type { ReactNode } from 'react';
import { EmptyState, PageLoading } from '../../components/StateViews';
import { useFamilyStore } from '../../store/useFamilyStore';
import { useNotificationStore } from '../../store/useNotificationStore';
import { useViewState } from '../../utils/useViewState';
import type { NotifyType } from '../../types/notification';
import { relativeTime, useNow } from './homeUtils';
import styles from './NotificationsPage.module.css';

/** 每种通知配一个图标，一眼能分出「要审批的」和「已通过的」 */
const TYPE_ICON: Record<NotifyType, ReactNode> = {
  checkin_pending: <ClockCircleOutlined />,
  approved: <CheckCircleOutlined />,
  rejected: <CloseCircleOutlined />,
  resubmitted: <RedoOutlined />,
  recorded: <EditOutlined />,
  payout: <GiftOutlined />,
};

type NoticeFilter = 'all' | 'unread';

/**
 * 通知收件箱。
 *
 * 这里只放「事件」（谁对谁做了什么）：妹妹提交了打卡、妈妈记了一笔、某条被驳回了……
 * 「今天任务没做完」「21 点了」这类待办提醒在首页即时算，不进这里 —— 否则每天都会刷屏。
 */
export default function NotificationsPage() {
  const navigate = useNavigate();
  const now = useNow();
  const role = useFamilyStore((s) => s.role);
  const { audience, items, unreadCount, loading, ready, load, markRead, markAllRead } =
    useNotificationStore();

  const [filter, setFilter] = useViewState<NoticeFilter>('home.noticeFilter', 'all');
  const [markingAll, setMarkingAll] = useState(false);

  useEffect(() => {
    load(role === 'parent' ? 'parent' : 'child').catch(() => undefined);
  }, [role, load]);

  const visible = filter === 'unread' ? items.filter((n) => n.status === 'unread') : items;

  const handleOpen = async (id: string, status: string, link?: string | null) => {
    if (status === 'unread') {
      markRead(id).catch(() => undefined);
    }
    if (link) navigate(link);
  };

  const handleMarkAll = async () => {
    setMarkingAll(true);
    try {
      await markAllRead();
      message.success('已全部标记为已读');
    } catch {
      message.error('操作失败，请重试');
    } finally {
      setMarkingAll(false);
    }
  };

  return (
    <div className={styles.page}>
      <div className={styles.head}>
        <button className={styles.back} onClick={() => navigate(-1)} aria-label="返回">
          <LeftOutlined />
        </button>
        <div className={styles.headText}>
          <div className={styles.title}>通知</div>
          <div className={styles.subtitle}>
            {audience === 'parent' ? '妹妹的打卡动态' : '妈妈说的话'}
            {unreadCount > 0 ? ` · ${unreadCount} 条未读` : ' · 都看过了'}
          </div>
        </div>
        <Button
          size="small"
          disabled={unreadCount === 0}
          loading={markingAll}
          onClick={handleMarkAll}
        >
          全部已读
        </Button>
      </div>

      {items.length > 0 && (
        <Segmented
          block
          value={filter}
          onChange={(value) => setFilter(value as NoticeFilter)}
          options={[
            { label: '全部', value: 'all' },
            { label: `未读${unreadCount > 0 ? ` (${unreadCount})` : ''}`, value: 'unread' },
          ]}
        />
      )}

      {!ready && !loading && (
        <div className={styles.notReady}>
          通知功能还没就绪（服务端通知表尚未创建），等家长执行一次数据库迁移就会出现。
        </div>
      )}

      {loading && items.length === 0 ? (
        <PageLoading />
      ) : visible.length === 0 ? (
        <EmptyState description={filter === 'unread' ? '没有未读通知' : '暂时没有通知'} />
      ) : (
        <div className={styles.list}>
          {visible.map((notice) => (
            <button
              key={notice.id}
              className={`${styles.item} ${notice.status === 'unread' ? styles.unread : ''}`}
              onClick={() => handleOpen(notice.id, notice.status, notice.link)}
            >
              <span className={`${styles.icon} ${styles[notice.type]}`}>
                {TYPE_ICON[notice.type as NotifyType] ?? <BellOutlined />}
              </span>
              <span className={styles.body}>
                <span className={styles.itemTitle}>{notice.title}</span>
                {notice.body && <span className={styles.itemBody}>{notice.body}</span>}
                <span className={styles.time}>{relativeTime(notice.created_at, now)}</span>
              </span>
              {notice.status === 'unread' && <span className={styles.dot} />}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
