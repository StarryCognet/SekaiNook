import { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Progress, message } from 'antd';
import {
  AccountBookOutlined,
  BookOutlined,
  CalendarOutlined,
  CheckOutlined,
  FireOutlined,
  NotificationOutlined,
  RightOutlined,
  SettingOutlined,
  SunOutlined,
  TrophyOutlined,
} from '@ant-design/icons';
import CheckInModal from '../../components/CheckInModal';
import RefreshFailedBar from '../../components/RefreshFailedBar';
import { getGardenIcon } from '../../components/garden/GardenIcon';
import { getTasksByType } from '../../config/familyRules';
import { useFamilyStore } from '../../store/useFamilyStore';
import { useGardenStore } from '../../store/useGardenStore';
import { useNotificationStore } from '../../store/useNotificationStore';
import { useKidName, useMomName } from '../../store/useSettingsStore';
import { useThemePalette } from '../../store/useThemeStore';
import { setViewState } from '../../utils/useViewState';
import { checkTask, isTaskDone } from '../../utils/taskRules';
import type { TaskConfig } from '../../types/family';
import {
  dateText,
  greetingText,
  recentSummary,
  relativeTime,
  todayRecords,
  useNow,
} from './homeUtils';
import styles from './KidHome.module.css';

/** 首页先摆这几个打卡按钮（顺序按妹妹最常用的排） */
const QUICK_TASK_IDS = [
  'finish_homework',
  'read_book',
  'clean_room',
  'take_out_trash',
  'sleep_on_time',
  'wash_dishes',
];

/** 被妈妈退回的申请看过就记在本机，最多留这么多条 */
const SEEN_REJECTS_KEY = 'sekainook_kid_seen_rejects';
const SEEN_REJECTS_MAX = 50;

/**
 * 妹妹版首页：一眼看到「今天要做什么、我赚了多少、妈妈说了什么」。
 * 大数字、大按钮，全部操作一次点击可达。
 */
export default function KidHome() {
  const navigate = useNavigate();
  const now = useNow();

  const {
    balance: sunBalance,
    tasks: gardenTasks,
    badges,
    streakDays,
    completedCount: gardenDone,
    init: initGarden,
    completeTask,
  } = useGardenStore();
  const { balance, records, pendingRecords, pendingCount, loadLedger } = useFamilyStore();
  const { items: notifications, unreadCount } = useNotificationStore();
  // 妹妹的视角：她自己一律是「我」，另一个人是妈妈（妈妈怎么被称呼由她在设置里定）
  const kidName = useKidName();
  const momName = useMomName();
  // 进度条这类 antd 组件吃不了 CSS 变量，颜色从当前主题的调色板里取
  const palette = useThemePalette();

  const [activeTask, setActiveTask] = useState<TaskConfig | null>(null);
  /** 拉取失败时页面要说话：不能把「没拉到」显示成「这周一分没赚」 */
  const [loadFailed, setLoadFailed] = useState(false);
  // 被妈妈退回的申请，看过一次就别老在孩子眼前晃（记在本机，不影响妈妈那边）
  const [seenRejects, setSeenRejects] = useState<string[]>(() => {
    try {
      const raw = localStorage.getItem(SEEN_REJECTS_KEY);
      const list = raw ? JSON.parse(raw) : [];
      return Array.isArray(list) ? list.filter((x): x is string => typeof x === 'string') : [];
    } catch {
      return [];
    }
  });

  // 花园存档放在 localStorage 里，原来只有花园页会 init —— 首页要用它，就得自己装一次
  useEffect(() => {
    initGarden();
  }, [initGarden]);

  const refresh = useCallback(async () => {
    try {
      await loadLedger();
      setLoadFailed(false);
    } catch {
      setLoadFailed(true);
    }
  }, [loadLedger]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  // 「我交的那条批了没有」是孩子最想知道的：20 秒问一次，页面在后台就跳过
  useEffect(() => {
    const tick = () => {
      if (document.hidden) return;
      void refresh();
    };
    const timer = setInterval(tick, 20000);
    document.addEventListener('visibilitychange', tick);
    window.addEventListener('focus', tick);
    return () => {
      clearInterval(timer);
      document.removeEventListener('visibilitychange', tick);
      window.removeEventListener('focus', tick);
    };
  }, [refresh]);

  const gardenTotal = gardenTasks.length;
  const gardenPercent = gardenTotal > 0 ? Math.round((gardenDone / gardenTotal) * 100) : 0;
  const learningLeft = gardenTotal - gardenDone;
  const earnedBadges = badges.filter((b) => b.earned).length;

  const week = recentSummary(records, 7, now);
  const todayCount = todayRecords(records, now).length;
  const showLateAlert = now.getHours() >= 21 && learningLeft > 0;

  // 还没做完的学习任务排前面，最多显示 4 个
  const todoTasks = gardenTasks.filter((t) => !t.done).slice(0, 4);

  const earningTasks = getTasksByType('earning');
  const quickTasks = QUICK_TASK_IDS.map((id) => earningTasks.find((t) => t.id === id)).filter(
    (t): t is TaskConfig => Boolean(t)
  );

  const latestNotice = notifications[0];

  // 最近一条「妈妈退回来了」：按时间倒序取第一条还没点过「知道了」的
  const rejected = records
    .filter((r) => r.status === 'rejected' && !seenRejects.includes(r.id))
    .sort((a, b) => (a.created_at < b.created_at ? 1 : -1))[0];
  // 退回的那条还能不能重交：得还认得出是哪个任务
  const rejectedTask = rejected
    ? [...earningTasks, ...getTasksByType('spending')].find((t) => t.id === rejected.task_id)
    : undefined;

  /** 「知道了」：这条退回不再提醒（下次退回的是新的一条，照样会提醒） */
  const dismissReject = (id: string) => {
    setSeenRejects((prev) => {
      const next = [...prev, id].slice(-SEEN_REJECTS_MAX);
      try {
        localStorage.setItem(SEEN_REJECTS_KEY, JSON.stringify(next));
      } catch {
        // 存不进去也不影响这一次
      }
      return next;
    });
  };

  /** 去花园的某个子页（顺手把菜单选好，落地就是那一页） */
  const goGarden = (menu: string) => {
    setViewState('garden.activeMenu', menu);
    navigate('/garden');
  };

  /** 去账本的某一页（打卡页 / 历史记录） */
  const goLedger = (tab: 'tasks' | 'records' | 'pending') => {
    setViewState('family.activeTab', tab);
    navigate('/family');
  };

  const entries = [
    { key: 'checkin', label: '去打卡', icon: <CheckOutlined />, onClick: () => goLedger('tasks') },
    { key: 'poem', label: '背古诗', icon: <BookOutlined />, onClick: () => goGarden('poem') },
    { key: 'garden', label: '我的花园', icon: <SunOutlined />, onClick: () => goGarden('garden') },
    {
      key: 'notice',
      label: `${momName}的话`,
      icon: <NotificationOutlined />,
      badge: unreadCount,
      onClick: () => navigate('/home/notifications'),
    },
    { key: 'plan', label: '本周计划', icon: <CalendarOutlined />, onClick: () => navigate('/family/plan') },
    { key: 'ledger', label: '我的账本', icon: <AccountBookOutlined />, onClick: () => goLedger('records') },
    { key: 'badge', label: '我的勋章', icon: <TrophyOutlined />, onClick: () => goGarden('rewards') },
    { key: 'settings', label: '设置', icon: <SettingOutlined />, onClick: () => navigate('/settings') },
  ];

  return (
    <div className={styles.page}>
      {/* 头像区：问候 + 阳光积分（花园的积分，孩子最有成就感的数字） */}
      <section className={styles.hero}>
        <div className={styles.heroTop}>
          <div>
            <div className={styles.heroGreeting}>{greetingText(now)}，{kidName}</div>
            <div className={styles.heroDate}>{dateText(now)}</div>
          </div>
          <button className={styles.heroAvatar} onClick={() => goGarden('rewards')} aria-label="我的勋章">
            🏅
          </button>
        </div>

        <div className={styles.heroSun}>
          <SunOutlined className={styles.heroSunIcon} />
          <span className={`num ${styles.heroSunValue}`}>{sunBalance}</span>
          <span className={styles.heroSunUnit}>阳光</span>
        </div>
        {/* 两种钱要分清：阳光是花园里的游戏币，下面的积分才是能跟妈妈兑现的 */}
        <div className={styles.heroSunHint}>花园里的阳光，只能在花园里花</div>

        <div className={styles.heroChips}>
          <span className={styles.heroChip}>
            <FireOutlined /> 连续 {streakDays} 天
          </span>
          <span className={styles.heroChip}>
            <TrophyOutlined /> 勋章 {earnedBadges}/{badges.length}
          </span>
        </div>
      </section>

      {/* 妈妈退回来的：把她的那句话摆在最上面，点一下就能重交 */}
      {rejected && (
        <section className={`${styles.card} ${styles.rejectCard}`}>
          <div className={styles.cardHead}>
            <span className={styles.cardTitle}>{momName}退回了一条</span>
            <button className={styles.rejectSeen} onClick={() => dismissReject(rejected.id)}>
              知道了
            </button>
          </div>
          <div className={styles.rejectTask}>
            <span>{rejected.task_name}</span>
            <span className={`num ${styles.rejectAmount}`}>
              {rejected.amount > 0 ? `+${rejected.amount}` : rejected.amount}
            </span>
          </div>
          <div className={styles.rejectReason}>
            {rejected.note || '看看哪里不对，改好可以再提交一次'}
          </div>
          {rejectedTask && (
            <button
              className={styles.rejectRetry}
              onClick={() => {
                dismissReject(rejected.id);
                setActiveTask(rejectedTask);
              }}
            >
              重新交一次 <RightOutlined />
            </button>
          )}
        </section>
      )}

      {/* 等妈妈看：交上去的申请现在到哪一步了，孩子不用瞎猜 */}
      {pendingCount > 0 && (
        <section className={styles.card}>
          <div className={styles.cardHead}>
            <span className={styles.cardTitle}>等{momName}看</span>
            <span className={styles.cardExtra}>还有 {pendingCount} 条没批</span>
          </div>
          <ul className={styles.pendingList}>
            {pendingRecords.slice(0, 3).map((r) => (
              <li key={r.id} className={styles.pendingItem}>
                <span className={styles.pendingName}>{r.task_name}</span>
                <span className={`num ${styles.pendingAmount}`}>
                  {r.amount > 0 ? `+${r.amount}` : r.amount}
                </span>
                <span className={styles.pendingTime}>{relativeTime(r.created_at, now)}</span>
              </li>
            ))}
          </ul>
          <div className={styles.pendingHint}>{momName}有空就会看，批了会自动加进我的积分</div>
          <button className={styles.cardLink} onClick={() => goLedger('pending')}>
            看看我交了什么 <RightOutlined />
          </button>
        </section>
      )}

      {/* 没拉到最新数据就说出来（不然「0 积分」会让孩子白难过一场） */}
      {loadFailed && <RefreshFailedBar onRetry={refresh} />}

      {/* 21 点还没做完学习任务：给一条能直接点走的提醒 */}
      {showLateAlert && (
        <button className={styles.alertBar} onClick={() => goGarden('tasks')}>
          <span>已经 21:00 啦，还有 {learningLeft} 个学习任务没完成</span>
          <RightOutlined />
        </button>
      )}

      {/* 今日学习任务 */}
      <section className={styles.card}>
        <div className={styles.cardHead}>
          <span className={styles.cardTitle}>今日学习任务</span>
          <span className={styles.cardExtra}>
            {gardenDone}/{gardenTotal}
          </span>
        </div>
        <Progress
          percent={gardenPercent}
          showInfo={false}
          strokeColor={{ '0%': palette.primarySoft, '100%': palette.primary }}
          trailColor="var(--color-border)"
          size="small"
        />
        {todoTasks.length === 0 ? (
          <div className={styles.allDone}>🎉 今天的任务全做完啦，去花园逛逛吧</div>
        ) : (
          <div className={styles.taskList}>
            {todoTasks.map((task) => (
              <button
                key={task.id}
                className={styles.taskItem}
                onClick={() => {
                  completeTask(task.id);
                  message.success(`+${task.reward} 阳光，${task.name}完成啦`);
                }}
              >
                <span className={styles.taskIcon}>{getGardenIcon(task.icon)}</span>
                <span className={styles.taskBody}>
                  <span className={styles.taskName}>{task.name}</span>
                  <span className={styles.taskMeta}>
                    {task.duration} 分钟 · +{task.reward} 阳光
                  </span>
                </span>
                <span className={styles.taskGo}>完成</span>
              </button>
            ))}
          </div>
        )}
        <button className={styles.cardLink} onClick={() => goGarden('tasks')}>
          去花园看全部任务 <RightOutlined />
        </button>
      </section>

      {/* 我的积分（家庭账本这一本账，跟妈妈兑现用） */}
      <section className={styles.card}>
        <div className={styles.cardHead}>
          <span className={styles.cardTitle}>我的积分</span>
          <span className={styles.cardExtra}>
            攒够可以跟{momName}兑现 · 今天打卡 {todayCount} 次
          </span>
        </div>

        <div className={styles.moneyRow}>
          <div className={styles.moneyValue}>
            <span className={`num ${styles.moneyNumber}`}>{balance}</span>
            <span className={styles.moneyUnit}>积分</span>
          </div>
          <div className={styles.moneySide}>
            <div>
              这一周赚了 <b className={styles.income}>+{week.income}</b>
            </div>
            <div>
              花掉 <b className={styles.expense}>{week.expense}</b>
            </div>
          </div>
        </div>

        <div className={styles.checkinGrid}>
          {quickTasks.map((task) => {
            const done = isTaskDone(task, records, now);
            return (
              <button
                key={task.id}
                className={styles.checkinBtn}
                disabled={done}
                onClick={() => setActiveTask(task)}
              >
                <span className={styles.checkinName}>{task.name}</span>
                <span className={`num ${styles.checkinValue}`}>{done ? '✓' : `+${task.value}`}</span>
              </button>
            );
          })}
        </div>

        <button className={styles.cardLink} onClick={() => goLedger('tasks')}>
          全部打卡任务 <RightOutlined />
        </button>
      </section>

      {/* 妈妈说的话：收件箱里最新的一条，点开是完整信箱 */}
      {latestNotice && (
        <button className={styles.noticeCard} onClick={() => navigate('/home/notifications')}>
          <div className={styles.noticeHead}>
            <NotificationOutlined /> {momName}说的话
            <span className={styles.noticeTime}>{relativeTime(latestNotice.created_at, now)}</span>
          </div>
          <div className={styles.noticeTitle}>{latestNotice.title}</div>
          {latestNotice.body && <div className={styles.noticeBody}>{latestNotice.body}</div>}
        </button>
      )}

      {/* 宫格入口：常用的一屏全在 */}
      <section className={styles.grid}>
        {entries.map((item) => (
          <button key={item.key} className={styles.gridItem} onClick={item.onClick}>
            <span className={styles.gridIcon}>
              {item.icon}
              {item.badge ? <span className={styles.gridBadge}>{item.badge > 99 ? '99+' : item.badge}</span> : null}
            </span>
            <span className={styles.gridLabel}>{item.label}</span>
          </button>
        ))}
      </section>

      <CheckInModal
        task={activeTask}
        isParent={false}
        guard={(task) => checkTask(task, records, now)}
        onClose={() => setActiveTask(null)}
        onSuccess={async () => {
          await loadLedger();
          message.success(`已提交，等${momName}审批`);
        }}
      />
    </div>
  );
}
