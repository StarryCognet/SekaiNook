import { useEffect, useState } from 'react';
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
import { getGardenIcon } from '../../components/garden/GardenIcon';
import { getTasksByType } from '../../config/familyRules';
import { useFamilyStore } from '../../store/useFamilyStore';
import { useGardenStore } from '../../store/useGardenStore';
import { useNotificationStore } from '../../store/useNotificationStore';
import { useKidName, useMomName } from '../../store/useSettingsStore';
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
  const { balance, records, loadLedger } = useFamilyStore();
  const { items: notifications, unreadCount } = useNotificationStore();
  // 妹妹的视角：她自己一律是「我」，另一个人是妈妈（妈妈怎么被称呼由她在设置里定）
  const kidName = useKidName();
  const momName = useMomName();

  const [activeTask, setActiveTask] = useState<TaskConfig | null>(null);

  // 花园存档放在 localStorage 里，原来只有花园页会 init —— 首页要用它，就得自己装一次
  useEffect(() => {
    initGarden();
  }, [initGarden]);

  useEffect(() => {
    loadLedger().catch(() => undefined);
  }, [loadLedger]);

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
            <span className={styles.heroEyebrow}>TODAY</span>
            <div className={styles.heroGreeting}>
              {greetingText(now)}，{kidName}
            </div>
            <div className={styles.heroDate}>{dateText(now)}</div>
          </div>
          <button className={styles.heroAvatar} onClick={() => goGarden('rewards')} aria-label="我的勋章">
            <TrophyOutlined />
          </button>
        </div>

        <div className={styles.heroSun}>
          <SunOutlined className={styles.heroSunIcon} />
          <span className={`num ${styles.heroSunValue}`}>{sunBalance}</span>
          <span className={styles.heroSunUnit}>阳光</span>
        </div>

        <div className={styles.heroChips}>
          <span className={styles.heroChip}>
            <FireOutlined /> 连续 {streakDays} 天
          </span>
          <span className={styles.heroChip}>
            <TrophyOutlined /> 勋章 {earnedBadges}/{badges.length}
          </span>
        </div>
      </section>

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
          <span>
            <span className={styles.cardTitle}>今日学习任务</span>
            <span className={styles.cardTitleEn}>DAILY TASKS</span>
          </span>
          <span className={styles.cardExtra}>
            {gardenDone}/{gardenTotal}
          </span>
        </div>
        <Progress
          percent={gardenPercent}
          showInfo={false}
          strokeColor={{ '0%': '#7fe8ff', '100%': '#0a84d8' }}
          trailColor="rgba(255, 255, 255, 0.1)"
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
          <span>
            <span className={styles.cardTitle}>我的积分</span>
            <span className={styles.cardTitleEn}>MY POINTS</span>
          </span>
          <span className={styles.cardExtra}>今天打卡 {todayCount} 次</span>
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
            <span className={styles.cardTitleEn}>MESSAGE</span>
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
