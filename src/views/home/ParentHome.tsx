import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Popconfirm, message } from 'antd';
import {
  AccountBookOutlined,
  AuditOutlined,
  CalendarOutlined,
  DownloadOutlined,
  NotificationOutlined,
  RightOutlined,
  SettingOutlined,
  SunOutlined,
  WalletOutlined,
} from '@ant-design/icons';
import { addLedgerRecord } from '../../api/familyLedger';
import { fetchWeeklyPlans } from '../../api/familyTasks';
import BalanceTrend from '../../components/BalanceTrend';
import { useFamilyStore } from '../../store/useFamilyStore';
import { useNotificationStore } from '../../store/useNotificationStore';
import { useKidName, useMomName } from '../../store/useSettingsStore';
import { exportLedgerCsv } from '../../utils/exportLedger';
import { setViewState } from '../../utils/useViewState';
import { getCurrentWeekLabel } from '../../utils/week';
import type { TaskConfig, WeeklyPlan } from '../../types/family';
import {
  clockText,
  dateText,
  greetingText,
  recentSummary,
  relativeTime,
  todayRecords,
  useNow,
} from './homeUtils';
import styles from './ParentHome.module.css';

/** 待办项：要么跳去处理，要么就地兑现 */
interface TodoItem {
  key: string;
  text: string;
  hint: string;
  kind: 'link' | 'settle';
  onGo?: () => void;
}

/**
 * 妈妈版首页：第一屏就是「有什么要我做」——
 * 待审批、可兑现、计划落后，点一下就能处理；下面是本周账目与女儿今天的流水。
 */
export default function ParentHome() {
  const navigate = useNavigate();
  const now = useNow(30000);

  const { balance, records, pendingCount, pendingRecords, loadLedger } = useFamilyStore();
  const { unreadCount } = useNotificationStore();
  // 妈妈的视角：她自己一律是「我」，另一个人是女儿（怎么称呼由妈妈在设置里定）
  const momName = useMomName();
  const kidName = useKidName();

  const [plans, setPlans] = useState<WeeklyPlan[]>([]);
  const [settling, setSettling] = useState(false);

  useEffect(() => {
    loadLedger().catch(() => undefined);
  }, [loadLedger]);

  // 本周计划进度（只读：没有计划就当作不落后，不去创建）
  useEffect(() => {
    let alive = true;
    fetchWeeklyPlans(getCurrentWeekLabel())
      .then((list) => {
        if (alive) setPlans(list);
      })
      .catch(() => undefined);
    return () => {
      alive = false;
    };
  }, []);

  const week = recentSummary(records, 7, now);
  const today = todayRecords(records, now);
  const planCurrent = plans.reduce((sum, p) => sum + p.current, 0);
  const planTarget = plans.reduce((sum, p) => sum + p.target, 0);
  const planPercent = planTarget > 0 ? Math.round((planCurrent / planTarget) * 100) : 0;
  // 均速基准：今天是一周的第几天，就该完成约几分之几
  const expectedPercent = Math.round(((now.getDay() + 1) / 7) * 100);
  const planBehind = planTarget > 0 && planPercent + 10 < expectedPercent;

  /** 去账本：顺手把 Tab 选到待审批 / 历史记录 */
  const goLedger = (tab: 'tasks' | 'records' | 'pending') => {
    setViewState('family.activeTab', tab);
    navigate('/family');
  };

  /**
   * 结算兑现（与账本页同一个口径）：把余额记成一条「现金兑现」支出，余额清零。
   * 家长在首页看到「可以兑现」就能直接办掉，不用再切到账本页找按钮。
   */
  const handleSettle = async () => {
    if (balance <= 0) return;
    setSettling(true);
    const amount = balance;
    try {
      const task: TaskConfig = {
        id: 'payout',
        name: '现金兑现',
        type: 'spending',
        value: -amount,
        unit: '元',
      };
      await addLedgerRecord(task, { note: '结算兑现，余额清零' }, { status: 'approved' });
      await loadLedger();
      message.success(`已兑现 ${amount} 积分，余额清零`);
    } catch (e) {
      message.error(e instanceof Error ? e.message : '结算失败，请重试');
    } finally {
      setSettling(false);
    }
  };

  const handleExport = () => {
    if (records.length === 0) {
      message.info('还没有流水可以导出');
      return;
    }
    message.success(`已导出 ${exportLedgerCsv(records)} 条记录`);
  };

  const todos: TodoItem[] = [];
  if (pendingCount > 0) {
    todos.push({
      key: 'pending',
      text: `有 ${pendingCount} 条打卡等你审批`,
      hint: pendingRecords[0] ? `最近：${pendingRecords[0].task_name}` : '点一下去处理',
      kind: 'link',
      onGo: () => goLedger('pending'),
    });
  }
  if (balance > 0) {
    todos.push({
      key: 'settle',
      text: `${kidName}攒了 ${balance} 积分，可以兑现了`,
      hint: `兑现 ${balance} 元，余额清零`,
      kind: 'settle',
    });
  }
  if (planBehind) {
    todos.push({
      key: 'plan',
      text: '本周学习计划进度落后',
      hint: `已完成 ${planPercent}%，差不多该到 ${expectedPercent}%`,
      kind: 'link',
      onGo: () => navigate('/family/plan'),
    });
  }

  const entries = [
    {
      key: 'pending',
      label: '去审批',
      icon: <AuditOutlined />,
      badge: pendingCount,
      onClick: () => goLedger('pending'),
    },
    {
      key: 'ledger',
      label: '家庭账本',
      icon: <AccountBookOutlined />,
      onClick: () => goLedger('records'),
    },
    {
      key: 'plan',
      label: '学习计划',
      icon: <CalendarOutlined />,
      onClick: () => navigate('/family/plan'),
    },
    { key: 'garden', label: '阳光花园', icon: <SunOutlined />, onClick: () => navigate('/garden') },
    {
      key: 'notice',
      label: '通知',
      icon: <NotificationOutlined />,
      badge: unreadCount,
      onClick: () => navigate('/home/notifications'),
    },
    {
      key: 'export',
      label: '导出流水',
      icon: <DownloadOutlined />,
      onClick: handleExport,
    },
    { key: 'settings', label: '设置', icon: <SettingOutlined />, onClick: () => navigate('/settings') },
  ];

  return (
    <div className={styles.page}>
      {/* 顶部：问候 + 实时时钟 + 两个最该看的数字 */}
      <section className={styles.hero}>
        <div className={styles.heroTop}>
          <div>
            <div className={styles.heroGreeting}>{greetingText(now)}，{momName}</div>
            <div className={styles.heroDate}>{dateText(now)}</div>
          </div>
          <div className={`num ${styles.heroClock}`}>{clockText(now)}</div>
        </div>

        <div className={styles.heroStats}>
          <button className={styles.heroStat} onClick={() => goLedger('pending')}>
            <span className={`num ${styles.heroStatValue}`}>{pendingCount}</span>
            <span className={styles.heroStatLabel}>待审批</span>
          </button>
          <div className={styles.heroDivider} />
          <button className={styles.heroStat} onClick={() => goLedger('records')}>
            <span className={`num ${styles.heroStatValue}`}>{balance}</span>
            <span className={styles.heroStatLabel}>当前余额（元）</span>
          </button>
        </div>
      </section>

      {/* 需要我处理：即时算出来的待办，不进收件箱 */}
      <section className={styles.card}>
        <div className={styles.cardHead}>
          <span className={styles.cardTitle}>需要我处理</span>
          {unreadCount > 0 && (
            <button className={styles.cardExtraLink} onClick={() => navigate('/home/notifications')}>
              还有 {unreadCount} 条新通知 <RightOutlined />
            </button>
          )}
        </div>

        {todos.length === 0 ? (
          <div className={styles.allDone}>都处理完了，今天很顺利 🎉</div>
        ) : (
          <div className={styles.todoList}>
            {todos.map((item) =>
              item.kind === 'settle' ? (
                <Popconfirm
                  key={item.key}
                  title={`兑现 ${balance} 积分？`}
                  description="会记一条「现金兑现」支出，余额清零"
                  okText="兑现"
                  cancelText="取消"
                  onConfirm={handleSettle}
                >
                  <button className={styles.todoItem} disabled={settling}>
                    <span className={styles.todoDot} />
                    <span className={styles.todoBody}>
                      <span className={styles.todoText}>{item.text}</span>
                      <span className={styles.todoHint}>{item.hint}</span>
                    </span>
                    <RightOutlined className={styles.todoArrow} />
                  </button>
                </Popconfirm>
              ) : (
                <button key={item.key} className={styles.todoItem} onClick={item.onGo}>
                  <span className={styles.todoDot} />
                  <span className={styles.todoBody}>
                    <span className={styles.todoText}>{item.text}</span>
                    <span className={styles.todoHint}>{item.hint}</span>
                  </span>
                  <RightOutlined className={styles.todoArrow} />
                </button>
              )
            )}
          </div>
        )}
      </section>

      {/* 本周概览：收入 / 支出 / 净额 / 打卡次数 + 近 14 天趋势 */}
      <section className={styles.card}>
        <div className={styles.cardHead}>
          <span className={styles.cardTitle}>本周概览</span>
          <span className={styles.cardExtra}>近 7 天</span>
        </div>
        <div className={styles.statRow}>
          <div className={styles.statCell}>
            <div className={`num ${styles.statValue} ${styles.income}`}>+{week.income}</div>
            <div className={styles.statLabel}>收入</div>
          </div>
          <div className={styles.statCell}>
            <div className={`num ${styles.statValue} ${styles.expense}`}>{week.expense}</div>
            <div className={styles.statLabel}>支出</div>
          </div>
          <div className={styles.statCell}>
            <div className={`num ${styles.statValue}`}>{week.net}</div>
            <div className={styles.statLabel}>净额</div>
          </div>
          <div className={styles.statCell}>
            <div className={`num ${styles.statValue}`}>{week.count}</div>
            <div className={styles.statLabel}>打卡次数</div>
          </div>
        </div>
        <BalanceTrend records={records} />
      </section>

      {/* 女儿今天：有新申请就在这儿能看见，点进去审批 */}
      <section className={styles.card}>
        <div className={styles.cardHead}>
          <span className={styles.cardTitle}>{kidName}今天</span>
          <span className={styles.cardExtra}>{today.length} 条</span>
        </div>

        {today.length === 0 ? (
          <div className={styles.allDone}>今天还没有新记录</div>
        ) : (
          <div className={styles.recordList}>
            {today.slice(0, 5).map((record) => (
              <div key={record.id} className={styles.recordItem}>
                <span className={styles.recordBody}>
                  <span className={styles.recordName}>{record.task_name}</span>
                  <span className={styles.recordMeta}>
                    {relativeTime(record.created_at, now)}
                    {record.status === 'pending' ? ' · 待审批' : record.status === 'rejected' ? ' · 已驳回' : ''}
                  </span>
                </span>
                <span
                  className={`num ${styles.recordAmount} ${record.amount > 0 ? styles.income : styles.expense}`}
                >
                  {record.amount > 0 ? `+${record.amount}` : record.amount}
                </span>
              </div>
            ))}
          </div>
        )}

        <button className={styles.cardLink} onClick={() => goLedger('records')}>
          看全部流水 <RightOutlined />
        </button>
      </section>

      {/* 宫格入口 */}
      <section className={styles.grid}>
        {entries.map((item) => (
          <button key={item.key} className={styles.gridItem} onClick={item.onClick}>
            <span className={styles.gridIcon}>
              {item.icon}
              {item.badge ? (
                <span className={styles.gridBadge}>{item.badge > 99 ? '99+' : item.badge}</span>
              ) : null}
            </span>
            <span className={styles.gridLabel}>{item.label}</span>
          </button>
        ))}
        <Popconfirm
          title={`兑现 ${balance} 积分？`}
          description="会记一条「现金兑现」支出，余额清零"
          okText="兑现"
          cancelText="取消"
          onConfirm={handleSettle}
        >
          <button className={styles.gridItem} disabled={balance <= 0 || settling}>
            <span className={styles.gridIcon}>
              <WalletOutlined />
            </span>
            <span className={styles.gridLabel}>结算兑现</span>
          </button>
        </Popconfirm>
      </section>
    </div>
  );
}
