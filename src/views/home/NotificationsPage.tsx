import { useEffect, useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
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
import RefreshFailedBar from '../../components/RefreshFailedBar';
import { EmptyState, ErrorState, PageLoading } from '../../components/StateViews';
import { useFamilyStore } from '../../store/useFamilyStore';
import { useNotificationStore } from '../../store/useNotificationStore';
import { useKidName, useMomName } from '../../store/useSettingsStore';
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
  const location = useLocation();
  const now = useNow();
  const role = useFamilyStore((s) => s.role);
  const { audience, items, unreadCount, loading, ready, error, load, markRead, markAllRead } =
    useNotificationStore();
  // 收件箱标题也按视角走：妈妈看的是女儿的动态，女儿看的是妈妈说的话
  const momName = useMomName();
  const kidName = useKidName();

  const [filter, setFilter] = useViewState<NoticeFilter>('home.noticeFilter', 'all');
  const [markingAll, setMarkingAll] = useState(false);

  /** 当前身份该看哪格信箱 */
  const targetAudience = role === 'parent' ? 'parent' : 'child';

  useEffect(() => {
    load(targetAudience).catch(() => undefined);
  }, [targetAudience, load]);

  const visible = filter === 'unread' ? items.filter((n) => n.status === 'unread') : items;

  // 失败态的重试：走 store 的加载动作（会进 loading），并带上当前信箱。
  // store 里的 audience 是上次实际尝试的信箱，优先用它，避免角色切换途中重试错格。
  const handleRetryLoad = () => {
    load(audience ?? targetAudience).catch(() => undefined);
  };

  // 冷启动/外部通知链接直达时，通知页就是 history 的入口（key 为 default），
  // 此时 navigate(-1) 会退出应用甚至回到站外页；退回首页并用 replace 换掉入口，避免死循环。
  const handleBack = () => {
    if (location.key === 'default') {
      navigate('/home', { replace: true });
      return;
    }
    navigate(-1);
  };

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
      // store 已把本地未读数拉回真实值，这里如实说明「没成功」，别让用户对不上账
      message.error('没能全部已读，请稍后重试');
    } finally {
      setMarkingAll(false);
    }
  };

  return (
    <div className={styles.page}>
      <div className={styles.head}>
        <button className={styles.back} onClick={handleBack} aria-label="返回">
          <LeftOutlined />
        </button>
        <div className={styles.headText}>
          <div className={styles.title}>通知</div>
          <div className={styles.subtitle}>
            {audience === 'parent' ? `${kidName}的打卡动态` : `${momName}说的话`}
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

      {/* 已经有旧数据时拉取失败：保留列表，只在顶部说明「看的是旧的」，不要把看过的通知藏起来 */}
      {error && items.length > 0 && (
        <RefreshFailedBar onRetry={handleRetryLoad} text="通知没刷新成功，下面是上次看到的内容" />
      )}

      {loading && items.length === 0 ? (
        <PageLoading />
      ) : error && items.length === 0 ? (
        // 加载失败必须看得见：以前这里会落进「暂时没有通知」空态，把断网说成没事
        <ErrorState description={error} onRetry={handleRetryLoad} />
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
