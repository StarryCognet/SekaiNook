import { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button, Input, InputNumber, Progress, message } from 'antd';
import { addLedgerRecord, LedgerApprovalError, describeSettleApplied, settleLedgerOncePerDay } from '../../api/familyLedger';
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
import { GARDEN_SHOP_ITEMS, toShopItemShortName } from '../../config/garden';
import { useFamilyStore } from '../../store/useFamilyStore';
import {
  USER_TASK_EXEC_ID,
  isRecordedToday,
  useCustomTasksStore,
} from '../../store/useCustomTasksStore';
import type { CustomTask } from '../../store/useCustomTasksStore';
import { useGardenStore } from '../../store/useGardenStore';
import { useNotificationStore } from '../../store/useNotificationStore';
import { useKidName, useMomName } from '../../store/useSettingsStore';
import { useThemePalette } from '../../store/useThemeStore';
import { setViewState } from '../../utils/useViewState';
import { checkTask, isTaskDone } from '../../utils/taskRules';
import type { TaskConfig } from '../../types/family';
import type { Badge } from '../../types/garden';
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

/** 新勋章只庆祝一次：本机记住已经庆祝过的勋章 id，免得每次打开都弹一遍 */
const CELEBRATED_BADGES_KEY = 'sekainook_badges_celebrated';

/** 读「已经庆祝过的勋章」；本机从来没记过时返回 null（= 第一次在这台设备上打开） */
function readCelebratedBadges(): string[] | null {
  try {
    const raw = localStorage.getItem(CELEBRATED_BADGES_KEY);
    if (raw === null) return null;
    const list = JSON.parse(raw);
    return Array.isArray(list) ? list.filter((x): x is string => typeof x === 'string') : [];
  } catch {
    // 存档坏了就当作第一次打开：只记不弹，总比每次刷新弹一堆好
    return null;
  }
}

/** 记下已经庆祝过的勋章（存不了也不影响页面） */
function writeCelebratedBadges(ids: string[]): void {
  try {
    localStorage.setItem(CELEBRATED_BADGES_KEY, JSON.stringify(ids));
  } catch {
    /* 本机存储不可用：退化成「不弹」 */
  }
}

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
    equippedAvatar,
    equippedTitle,
    init: initGarden,
    completeTask,
  } = useGardenStore();
  const { balance, records, pendingRecords, pendingCount, loadLedger } = useFamilyStore();
  // 我的任务（本地任务列表，不加表）：预置两条 + 妈妈加的 + 我自己加的
  const customTasks = useCustomTasksStore((s) => s.tasks);
  const addCustomTask = useCustomTasksStore((s) => s.addTask);
  const ensurePresets = useCustomTasksStore((s) => s.ensurePresets);
  const markTaskDone = useCustomTasksStore((s) => s.markDone);
  const isTaskDoneToday = useCustomTasksStore((s) => s.isDoneToday);
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
  // 刚解锁的勋章：有一个就弹一次（仪式感），点掉就没了
  const [newBadge, setNewBadge] = useState<Badge | null>(null);
  // 自己加任务的小表单：只写进任务列表，不入账
  const [wishName, setWishName] = useState('');
  const [wishValue, setWishValue] = useState<number | null>(5);
  /** 正在打卡的任务 id：防连点 */
  const [checkingId, setCheckingId] = useState<string | null>(null);

  // 花园存档放在 localStorage 里，原来只有花园页会 init —— 首页要用它，就得自己装一次
  useEffect(() => {
    initGarden();
  }, [initGarden]);

  // 预置的两条学习任务要出现在「我的任务」里，即使妈妈没打开过家长页。
  // ensurePresets 幂等：重复调用不会产生重复项，也不会覆盖改过 / 删过的任务。
  useEffect(() => {
    ensurePresets();
  }, [ensurePresets]);

  const refresh = useCallback(async () => {
    try {
      await loadLedger();
      setLoadFailed(false);
    } catch {
      setLoadFailed(true);
      return;
    }
    // 日结算（开户礼金 / 那天完成的任务不够 5 个 / 到 22:00 没打卡睡觉）：
    // 正确性由服务端幂等 id 保证，本地只按「被结算的那一天」节流，纯粹为了省流量。
    const settled = await settleLedgerOncePerDay();
    if (!settled || settled.applied.length === 0) return;
    await loadLedger().catch(() => undefined);
    message.warning({ content: `账本更新：${describeSettleApplied(settled.applied)}`, duration: 6 });
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

  // 解锁新勋章要有仪式感，但同一枚不能每次打开都弹：
  // 本机记一份「已经庆祝过」的，第一次打开时把当时已有的都算作早就知道
  useEffect(() => {
    const earnedIds = badges.filter((b) => b.earned).map((b) => b.id);
    const stored = readCelebratedBadges();
    if (stored === null) {
      writeCelebratedBadges(earnedIds);
      return;
    }
    const fresh = badges.find((b) => b.earned && !stored.includes(b.id));
    if (!fresh) return;
    writeCelebratedBadges([...stored, fresh.id]);
    setNewBadge(fresh);
  }, [badges]);

  const gardenTotal = gardenTasks.length;
  const gardenPercent = gardenTotal > 0 ? Math.round((gardenDone / gardenTotal) * 100) : 0;
  const learningLeft = gardenTotal - gardenDone;
  const earnedBadges = badges.filter((b) => b.earned).length;
  // 孩子买到的东西要看得见：头像框与称号从商城物品里翻出来（称号名字去掉「称号・」前缀）；
  // 两样都没买时下面一个多余的元素都不渲染，视觉与以前完全一致
  const avatarItem = GARDEN_SHOP_ITEMS.find((item) => item.id === equippedAvatar);
  const titleItem = GARDEN_SHOP_ITEMS.find((item) => item.id === equippedTitle);
  const titleText = titleItem ? toShopItemShortName(titleItem.name) : null;

  const week = recentSummary(records, 7, now);
  const todayCount = todayRecords(records, now).length;
  const showLateAlert = now.getHours() >= 22 && learningLeft > 0;

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

  /**
   * 我的任务打卡：写一条 `user_task_exec` 流水（预置任务用服务端登记的 id，各自独立、即时到账）。
   *
   * ⚠️ 绝不自造 `custom_<ts>` 之类的 id 去写账本 —— 服务端对未知 task_id 一律 403。
   * 妈妈加的任务打完卡直接入账；我自己加的要走 pending 等妈妈批，
   * 否则就成了「自己加任务自己发钱」，是刷分口子。
   */
  const handleMyTaskCheckIn = async (task: CustomTask) => {
    if (checkingId) return;
    setCheckingId(task.id);
    try {
      const execTask: TaskConfig = {
        // 预置两条在服务端有各自登记的 id（各自日限 1、autoApprove 即时到账）
        id: task.kind === 'preset' ? task.id : USER_TASK_EXEC_ID,
        name: task.name,
        type: task.type,
        value: task.value,
        unit: '积分',
      };
      await addLedgerRecord(execTask, undefined, { autoApprove: task.createdBy === 'parent' });
      markTaskDone(task.id);
      await loadLedger();
      message.success(
        task.createdBy === 'parent'
          ? `「${task.name}」打卡成功`
          : `「${task.name}」已提交，等${momName}审批`
      );
    } catch (e) {
      if (e instanceof LedgerApprovalError) {
        // 账其实已经记上了，只是「立即入账」那一步没成功：这条以 pending 躺在待审批里，
        // 所以本地也要算今天已完成 —— 不然孩子再点一次，只会撞上服务端的同名日限。
        markTaskDone(task.id);
        await loadLedger().catch(() => undefined);
        message.warning({ content: e.message, duration: 6 });
        return;
      }
      // 服务端的三层日限闸门（同名当日重复 / 当日条数 ≥20 / 当日正分累计 ≥50）都返回 409，
      // 文案照实提示 —— 本地置灰只是省一次白跑的请求，权威永远在服务端。
      message.error(e instanceof Error ? e.message : '打卡失败，请重试');
    } finally {
      setCheckingId(null);
    }
  };

  /** 自己加一个任务：只写进任务列表，**不入账**；完成时提交，等妈妈批了才加分 */
  const handleAddWish = () => {
    const name = wishName.trim();
    if (!name) {
      message.info('先写一个任务名吧');
      return;
    }
    addCustomTask({ name, value: wishValue ?? 5, type: 'earning', createdBy: 'child' });
    setWishName('');
    setWishValue(5);
    message.success(`「${name}」加好啦，完成时点一下，等${momName}批了就有分`);
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
            <div className={styles.heroGreeting}>
              {greetingText(now)}，{kidName}
              {/* 买到称号才挂这个胶囊：没买的时候不留空位 */}
              {titleText && <span className={styles.heroTitleTag}>{titleText}</span>}
            </div>
            <div className={styles.heroDate}>{dateText(now)}</div>
          </div>
          <button
            className={`${styles.heroAvatar} ${avatarItem ? styles.heroAvatarFramed : ''}`}
            onClick={() => goGarden('rewards')}
            aria-label="我的勋章"
          >
            🏅
            {/* 戴了头像框：右下角别上这件头像框自己的图标（太阳 / 星星） */}
            {avatarItem && (
              <span className={styles.heroAvatarBadge}>{getGardenIcon(avatarItem.icon)}</span>
            )}
          </button>
        </div>

        <div className={styles.heroSun}>
          <SunOutlined className={styles.heroSunIcon} />
          <span className={`num ${styles.heroSunValue}`}>{sunBalance}</span>
          <span className={styles.heroSunUnit}>积分</span>
        </div>
        {/* 两种钱要分清：阳光是花园里的游戏币，下面的积分才是能跟妈妈兑现的 */}
        <div className={styles.heroSunHint}>花园里的阳光，会存进家里的账本，换手机也在</div>

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

      {/* 22 点还没做完学习任务：给一条能直接点走的提醒 */}
      {showLateAlert && (
        <button className={styles.alertBar} onClick={() => goGarden('tasks')}>
          <span>已经 22:00 啦，还有 {learningLeft} 个学习任务没完成</span>
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
                  // store 会挡下重复打卡（含连点两次）：这时不能报喜，
                  // 不然孩子以为又赚了一份阳光，翻过去数字却没变
                  const done = useGardenStore
                    .getState()
                    .tasks.some((t) => t.id === task.id && t.done);
                  if (!done) {
                    message.info(`「${task.name}」今天已经完成过啦`);
                    return;
                  }
                  message.success(`+${task.reward} 积分，${task.name}完成啦`);
                }}
              >
                <span className={styles.taskIcon}>{getGardenIcon(task.icon)}</span>
                <span className={styles.taskBody}>
                  <span className={styles.taskName}>{task.name}</span>
                  <span className={styles.taskMeta}>
                    {task.duration} 分钟 · +{task.reward} 积分
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

      {/* 我的任务（本地任务列表：预置两条 + 妈妈加的 + 我自己加的）：点一下才算完成 */}
      <section className={styles.card}>
        <div className={styles.cardHead}>
          <span className={styles.cardTitle}>我的任务</span>
          <span className={styles.cardExtra}>完成一个打一次卡</span>
        </div>
        {customTasks.length === 0 ? (
          <div className={styles.allDone}>还没有任务，让{momName}加一个，或者自己加一个</div>
        ) : (
          <div className={styles.taskList}>
            {customTasks.map((task) => {
              // 服务端才是权威：这里置灰只是省一次注定 409 的请求
              const done = isRecordedToday(task, records, now) || isTaskDoneToday(task.id);
              return (
                <button
                  key={task.id}
                  className={styles.taskItem}
                  disabled={done || checkingId === task.id}
                  onClick={() => void handleMyTaskCheckIn(task)}
                >
                  <span className={styles.taskBody}>
                    <span className={styles.taskName}>{task.name}</span>
                    <span className={styles.taskMeta}>
                      {task.kind === 'preset'
                        ? '每天可以做一次'
                        : task.createdBy === 'child'
                          ? `我加的 · 要${momName}批`
                          : `${momName}加的`}
                    </span>
                  </span>
                  <span className={`num ${styles.checkinValue}`}>
                    {done ? '✓' : task.value > 0 ? `+${task.value}` : task.value}
                  </span>
                </button>
              );
            })}
          </div>
        )}

        {/* 自己加一个：只写进任务列表，不入账（需求 5） */}
        <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
          <Input
            value={wishName}
            onChange={(e) => setWishName(e.target.value)}
            placeholder="我想做的任务"
            maxLength={20}
          />
          <InputNumber
            value={wishValue}
            onChange={setWishValue}
            min={1}
            max={200}
            style={{ width: 96 }}
            placeholder="积分"
          />
          <Button type="primary" onClick={handleAddWish}>
            加一个
          </Button>
        </div>
        <div className={styles.pendingHint}>
          自己加的任务不会马上加分：完成时提交，{momName}批了才进账本
        </div>
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
      {/* 解锁新勋章的仪式感：压暗整屏，中间弹一张卡，点掉即收下 */}
      {newBadge && (
        <div className={styles.badgeCelebrate} role="dialog" aria-modal="true">
          <div className={styles.badgeCelebrateCard}>
            <div className={styles.badgeCelebrateIcon}>{getGardenIcon(newBadge.icon)}</div>
            <div className={styles.badgeCelebrateLabel}>解锁新勋章</div>
            <div className={styles.badgeCelebrateName}>{newBadge.name}</div>
            <div className={styles.badgeCelebrateDesc}>{newBadge.description}</div>
            <button className={styles.badgeCelebrateBtn} onClick={() => setNewBadge(null)}>
              好耶，收下啦
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
