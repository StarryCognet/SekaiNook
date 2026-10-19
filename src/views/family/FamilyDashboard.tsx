import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Button, Card, List, Tag, Tabs, Form, Input, Select, InputNumber, Image, message, Badge, Popconfirm, Segmented, Modal, Spin, Switch } from 'antd';
import {
  PlusOutlined,
  MinusOutlined,
  MoonOutlined,
  CheckCircleOutlined,
  WalletOutlined,
  ClockCircleOutlined,
  RiseOutlined,
  FallOutlined,
  HistoryOutlined,
  AppstoreOutlined,
  EyeOutlined,
  AuditOutlined,
  CloseCircleOutlined,
  DeleteOutlined,
  RollbackOutlined,
  DownloadOutlined,
  DownOutlined,
  UpOutlined,
  CameraOutlined,
} from '@ant-design/icons';
import { addLedgerRecord, LedgerApprovalError, describeSettleApplied, resubmitRequest, settleLedgerOncePerDay } from '../../api/familyLedger';
import { useViewState } from '../../utils/useViewState';
import { exportLedgerCsv } from '../../utils/exportLedger';
import { checkTask, isTaskDone } from '../../utils/taskRules';
import { getTasksByType, pointsToYuan, EXCHANGE_RATE_TEXT } from '../../config/familyRules';
import { useFamilyStore } from '../../store/useFamilyStore';
import {
  useCustomTasksStore,
  USER_TASK_EXEC_ID,
  isRecordedToday,
  beijingDayKey,
} from '../../store/useCustomTasksStore';
import type { CustomTask } from '../../store/useCustomTasksStore';
import { PageLoading, EmptyState, ErrorState } from '../../components/StateViews';
import BalanceTrend from '../../components/BalanceTrend';
import CheckInModal from '../../components/CheckInModal';
import { designTokens } from '../../theme/tokens';
import type { LedgerRecord, LedgerStatus, TaskConfig, TaskType } from '../../types/family';
import styles from './FamilyDashboard.module.css';

/**
 * 历史记录一次展示的天数。
 * 改成**按天分页**（原来是按 20 条分页）：分组后按条数切会把同一天拦腰截断，
 * 一屏里冒出两个「今天」的组头 —— 按天切就不会。
 */
const RECORDS_PAGE_DAYS = 7;

/** 历史记录状态筛选值：全部 / 待审批 / 已入账 / 已驳回 */
type RecordFilter = 'all' | LedgerStatus;

/** 自定义任务表单值 */
interface CustomTaskForm {
  type: TaskType;
  name: string;
  value: number;
  /** 提交这条任务是否必须带一张照片（仅赚钱类可见 / 生效） */
  requirePhoto?: boolean;
}

/**
 * 快捷任务区里的一条按钮 —— 内置任务与自定义任务在这里统一成同一种形状，
 * 免得「赚钱 / 消费罚款」×「内置 / 自定义」四段 JSX 各写一遍。
 */
interface TaskEntry {
  /** React key（自定义任务用本地 id，它和提交时用的执行 task_id 不是一回事） */
  key: string;
  /** 点开后交给打卡弹窗的任务 */
  task: TaskConfig;
  /** 来自哪条自定义任务（提交成功要标成「今天做过」）；内置任务为 null */
  custom: CustomTask | null;
  /** 今天是否已达上限（已达的收进「今日已完成」，不再占着任务区） */
  done: boolean;
}

/** 历史记录按天分组后的一天 */
interface DayGroup {
  /** 东八区日历天 YYYY-MM-DD（与服务端日限 / 结算同一时区） */
  key: string;
  /** 组标题：今天 / 昨天 / 8月12日 周三 */
  label: string;
  records: LedgerRecord[];
  /** 当天【已入账】净额 —— 口径与余额一致（无 status 或 approved）；待审批、已驳回不计 */
  net: number;
  /** 当天待审批条数（免得家长把小计当成已经到账） */
  pendingCount: number;
}

/** 东八区日历天 → 「今天 / 昨天 / 8月12日 周三」 */
function formatDayLabel(dayKey: string, todayKey: string, yesterdayKey: string): string {
  if (dayKey === todayKey) return '今天';
  if (dayKey === yesterdayKey) return '昨天';
  const parts = dayKey.split('-').map(Number);
  const year = parts[0];
  const month = parts[1];
  const day = parts[2];
  if (year === undefined || month === undefined || day === undefined) return dayKey;
  if (!Number.isFinite(year) || !Number.isFinite(month) || !Number.isFinite(day)) return dayKey;
  const at = new Date(Date.UTC(year, month - 1, day));
  const week = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][at.getUTCDay()];
  // 同一年不写年份（「8月12日 周三」比「2025年8月12日 周三」好扫）
  return dayKey.slice(0, 4) === todayKey.slice(0, 4)
    ? `${month}月${day}日 ${week}`
    : `${year}年${month}月${day}日 ${week}`;
}

/** 核心仪表盘：积分银行 + 任务区 / 待审批区 / 历史记录区 */
export default function FamilyDashboard() {
  const {
    balance,
    records,
    pendingRecords,
    pendingCount,
    loading,
    role,
    loadLedger,
    refreshPending,
    approve,
    approveMany,
    reject,
    removeRecord,
  } = useFamilyStore();
  const [error, setError] = useState<string | null>(null);
  /** 错误页上有人点了重试：给一个「正在重试」的反馈 */
  const [retrying, setRetrying] = useState(false);
  const [now, setNow] = useState(new Date());
  // 当前分页（任务区 / 待审批 / 历史记录）—— 切到别的页面再回来要还在原来那页
  const [activeTab, setActiveTab] = useViewState('family.activeTab', 'tasks');
  const [form] = Form.useForm<CustomTaskForm>();
  /** 「添加任务」表单里选中的类型 —— 「必须添加照片」这个开关只在赚钱类下出现 */
  const customFormType = Form.useWatch('type', form);
  /** 驳回弹窗：正在驳回哪一条 + 家长写给孩子的那句话 */
  const [rejectTarget, setRejectTarget] = useState<LedgerRecord | null>(null);
  const [rejectReason, setRejectReason] = useState('');
  const [rejecting, setRejecting] = useState(false);
  const [approvingAll, setApprovingAll] = useState(false);
  /** 正在审批的记录 id（按条加 loading，防止连点重复提交） */
  const [approvingIds, setApprovingIds] = useState<ReadonlySet<string>>(() => new Set());

  const isParent = role === 'parent';

  // 自定义任务列表（本地存档，不加表）：家长加的任务都在这里，打卡完成才给积分
  const customTasks = useCustomTasksStore((s) => s.tasks);
  const addCustomTask = useCustomTasksStore((s) => s.addTask);
  const removeCustomTask = useCustomTasksStore((s) => s.removeTask);
  const ensurePresets = useCustomTasksStore((s) => s.ensurePresets);
  const markTaskDone = useCustomTasksStore((s) => s.markDone);
  const isTaskDoneToday = useCustomTasksStore((s) => s.isDoneToday);

  /**
   * 「待审批」Tab 只对家长存在，而 activeTab 是按 key 记的（跨身份共用同一份存储）。
   * 家长停在待审批、切回小孩身份再进账本时，activeKey 指向一个不存在的 Tab，内容区就是空白。
   * 这里让小孩端回落到任务区：不动存储 key —— KidHome.tsx / ParentHome.tsx 也在写 family.activeTab，
   * 改 key 得同时改清单外的文件，漏一个就写错地方；家长原来的选择也照样留着。
   */
  const visibleTab = !isParent && activeTab === 'pending' ? 'tasks' : activeTab;

  // 任务打卡弹窗状态（照片与备注草稿由 CheckInModal 自己管）
  const [activeTask, setActiveTask] = useState<TaskConfig | null>(null);
  /**
   * 弹窗是从哪条自定义任务打开的：提交成功后要把它标成「今天做过」。
   * 打开内置任务时置空；关闭弹窗**不清**（CheckInModal 是「先 close 再 onSuccess」，
   * 这里清了 onSuccess 就找不到它了）。
   */
  const modalCustomTaskRef = useRef<CustomTask | null>(null);
  /** 正在兑换现金（家长） */
  const [settling, setSettling] = useState(false);
  /** 兑换区输入框里的积分数（null = 还没填，视为 0） */
  const [exchangePoints, setExchangePoints] = useState<number | null>(null);
  /** 历史记录状态筛选 + 已渲染天数（按天分页）—— 跨页面切换保留，切走再回来还是原样 */
  const [recordFilter, setRecordFilter] = useViewState<RecordFilter>('family.recordFilter', 'all');
  const [visibleDays, setVisibleDays] = useViewState<number>('family.visibleDays', RECORDS_PAGE_DAYS);
  /** 首次挂载不算「切换筛选」，否则会把恢复出来的分页进度清零 */
  const filterMountedRef = useRef(false);
  /** 「今日已完成」是否展开（默认收起：做完的任务不该继续占着任务区） */
  const [showDoneTasks, setShowDoneTasks] = useState(false);
  /** 家长的自定义任务管理区是否展开（默认收起：表单不该天天占着屏幕） */
  const [showCustomManager, setShowCustomManager] = useState(false);
  /** 兑现弹窗开关（余额卡上只留一个按钮，填写与确认都在弹窗里） */
  const [settleOpen, setSettleOpen] = useState(false);

  const earningTasks = getTasksByType('earning');
  const spendingTasks = getTasksByType('spending');
  /** 自定义任务（家长加的 / 孩子提的）：也摆进「快捷任务」区，点一下就是打卡 */
  const customEarningTasks = customTasks.filter((t) => t.type === 'earning');
  const customSpendingTasks = customTasks.filter((t) => t.type === 'spending');
  /** 右侧快捷按钮对应的任务（可能不存在，避免用非空断言） */
  const homeworkTask = earningTasks.find((t) => t.id === 'finish_homework');
  const sleepTask = earningTasks.find((t) => t.id === 'sleep_on_time');

  /**
   * 自定义任务在服务端要有对应的「执行 id」：预置两条各走自己的 id（日限 1、即时到账），
   * 其余全部写 `user_task_exec`，服务端按**任务名**判重 + 三层闸门。
   * 快捷任务区把自定义任务也摆成按钮，点开后走**同一个打卡弹窗**（可传照片 / 写备注），
   * 不再点一下就立刻加积分 —— 与内置任务的操作完全一致。
   */
  const toExecTask = (task: CustomTask): TaskConfig => ({
    id: task.kind === 'preset' ? task.id : USER_TASK_EXEC_ID,
    name: task.name,
    type: task.type,
    value: task.value,
    unit: '积分',
    // 家长在「添加任务」里定的照片要求，原样带进打卡弹窗
    requirePhoto: task.requirePhoto,
  });

  /** 自定义任务今天是否已经做过（账本里已有流水，或本机标记过） */
  const customTaskDone = (task: CustomTask): boolean =>
    isRecordedToday(task, records, now) || isTaskDoneToday(task.id);

  /** 内置任务 → 按钮条目 */
  const toEntry = (task: TaskConfig, done: boolean): TaskEntry => ({
    key: task.id,
    task,
    custom: null,
    done,
  });

  /**
   * 快捷任务按「今天做完没有」分成两组：待做留在明面上，做完的收进「今日已完成」折叠区，
   * 这样列表只会越用越短。判断与打卡置灰（isTaskDone）同一套规则 ——
   * 日限没满的任务（比如每天 2 次的洗碗）打完一次仍然留在待做里。
   */
  const earningEntries: TaskEntry[] = [
    ...earningTasks.map((task) => toEntry(task, isTaskDone(task, records, now))),
    ...customEarningTasks.map((task) => ({
      key: task.id,
      task: toExecTask(task),
      custom: task,
      done: customTaskDone(task),
    })),
  ];
  const spendingEntries: TaskEntry[] = [
    ...spendingTasks.map((task) => toEntry(task, isTaskDone(task, records, now))),
    ...customSpendingTasks.map((task) => ({
      key: task.id,
      task: toExecTask(task),
      custom: task,
      done: customTaskDone(task),
    })),
  ];
  /** 今日已完成的任务（两组加起来，用于折叠行文案与展开后的列表） */
  const doneEntries = [...earningEntries, ...spendingEntries].filter((entry) => entry.done);

  /** 历史记录：按状态筛选（all = 全部） */
  const filteredRecords = useMemo(
    () => (recordFilter === 'all' ? records : records.filter((r) => (r.status ?? 'approved') === recordFilter)),
    [records, recordFilter]
  );

  /**
   * 历史记录按天分组：组头给「今天 / 昨天 / 8月12日 周三」+ 当天净额小计，条目挂在下面。
   * 净额口径与余额完全一致（无 status 或 approved），所以每天的小计加起来就是那天的账面变化；
   * 待审批只报条数、不进小计 —— 钱还没到账，不能算进去。
   * 分天用东八区（与服务端日限 / 结算同一时区），否则晚上 8 点后本机会把今天算成明天。
   */
  const todayKey = beijingDayKey(now);
  const yesterdayKey = beijingDayKey(new Date(now.getTime() - 24 * 60 * 60 * 1000));
  const dayGroups: DayGroup[] = [];
  const dayIndex = new Map<string, DayGroup>();
  for (const record of filteredRecords) {
    const at = new Date(record.created_at);
    const key = Number.isNaN(at.getTime()) ? 'unknown' : beijingDayKey(at);
    let group = dayIndex.get(key);
    if (!group) {
      group = { key, label: formatDayLabel(key, todayKey, yesterdayKey), records: [], net: 0, pendingCount: 0 };
      dayIndex.set(key, group);
      dayGroups.push(group);
    }
    group.records.push(record);
    const status = record.status ?? 'approved';
    if (status === 'approved') group.net += record.amount;
    if (status === 'pending') group.pendingCount += 1;
  }
  // 按天倒序：新的一天永远在最前（接口顺序变了也不会乱）
  dayGroups.sort((a, b) => (a.key < b.key ? 1 : a.key > b.key ? -1 : 0));
  /** 当前已渲染的天（「加载更多」按天加，不会把同一天切成两段） */
  const visibleGroups = dayGroups.slice(0, visibleDays);
  /** 还没露面的天数（给「加载更多」写文案） */
  const hiddenDayCount = dayGroups.length - visibleGroups.length;

  /**
   * 拉账本：**成功才清掉 error** —— 以前全文件没有 setError(null)，
   * 点「重试」就算成功也会一直停在错误页。重试期间用 retrying 给出反馈。
   */
  const reloadLedger = useCallback(async () => {
    setRetrying(true);
    try {
      await loadLedger();
      setError(null);
      // 日结算（开户礼金 / 那天完成的任务不够 5 个 / 到 22:00 没打卡睡觉）：
      // 正确性由服务端幂等 id 保证，本地按「被结算的那一天」节流，纯粹为了省流量。
      const settled = await settleLedgerOncePerDay();
      if (settled && settled.applied.length > 0) {
        await loadLedger().catch(() => undefined);
        message.warning({
          content: `账本更新：${describeSettleApplied(settled.applied)}`,
          duration: 6,
        });
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : '加载失败');
    } finally {
      setRetrying(false);
    }
  }, [loadLedger]);

  // 初始化加载
  useEffect(() => {
    void reloadLedger();
  }, [reloadLedger]);

  // 切换筛选条件后回到第一页，避免出现「筛完还剩 40 条已渲染」
  // 首次挂载跳过：从别的页面切回来时要保住原来的分页进度
  useEffect(() => {
    if (!filterMountedRef.current) {
      filterMountedRef.current = true;
      return;
    }
    setVisibleDays(RECORDS_PAGE_DAYS);
  }, [recordFilter, setVisibleDays]);

  // 每秒刷新当前时间（用于作息判断）
  useEffect(() => {
    const timer = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(timer);
  }, []);

  // 预置的两条学习任务（十个英语单词 / 两首古诗）默认出现在任务列表里。
  // ensurePresets 幂等：重复调用不产生重复项，也不会覆盖家长改过 / 删过的任务。
  useEffect(() => {
    ensurePresets();
  }, [ensurePresets]);

  // 家长端：轮询待审批数量（角标实时性），10s 间隔 + 页面重新可见时立即刷新。
  // 页面在后台（息屏/切走）时跳过轮询，省电也省流量 —— 安卓手机上这点很重要
  useEffect(() => {
    if (!isParent) return;
    const refresh = () => {
      if (document.hidden) return;
      refreshPending().catch(() => undefined);
    };
    const timer = setInterval(refresh, 10000);
    const onVisible = () => {
      if (!document.hidden) refresh();
    };
    document.addEventListener('visibilitychange', onVisible);
    window.addEventListener('focus', onVisible);
    return () => {
      clearInterval(timer);
      document.removeEventListener('visibilitychange', onVisible);
      window.removeEventListener('focus', onVisible);
    };
  }, [isParent, refreshPending]);

  // 小孩端：放宽到 15s 轮询流水，感知审批结果；同样在后台暂停，回到前台立刻补一次
  useEffect(() => {
    if (isParent) return;
    const refresh = () => {
      if (document.hidden) return;
      loadLedger().catch(() => undefined);
    };
    const timer = setInterval(refresh, 15000);
    const onVisible = () => {
      if (!document.hidden) refresh();
    };
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      clearInterval(timer);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [isParent, loadLedger]);

  const hour = now.getHours();
  // 22:00 后仍未打卡睡觉：服务端会按 settleDay 自动记一笔 -20「未按时作息(晚于22:00)」
  const isLate = hour >= 22;

  /** 打卡规则的判断在 utils/taskRules 里 —— 首页（妹妹版）用的是同一套规则 */
  const guardTask = (task: TaskConfig) => checkTask(task, records, now);
  const isDone = (task: TaskConfig) => isTaskDone(task, records, now);

  /** 撤销刚才的打卡 */
  const handleUndo = async (recordId: string) => {
    try {
      await removeRecord(recordId);
      message.info('已撤销刚才的打卡');
    } catch {
      message.error('撤销失败，请到「历史记录」里删除');
    }
  };

  /** 打卡成功提示：5 秒内可撤销（手机误触兜底） */
  const notifySuccess = (task: TaskConfig, recordId: string) => {
    const sign = task.value > 0 ? '+' : '';
    const text = isParent
      ? `${sign}${task.value} 积分！${task.name}`
      : `已提交「${task.name}」，等家长审批`;
    message.open({
      type: 'success',
      duration: 5,
      content: (
        <span className={styles.undoToast}>
          {text}
          <Button size="small" type="link" onClick={() => handleUndo(recordId)}>
            撤销
          </Button>
        </span>
      ),
    });
  };

  /**
   * 打开打卡弹窗 —— 内置任务与自定义任务都走这一条路。
   *
   * 以前「按时完成作业」「按时睡觉」两个快捷按钮是**直接写流水**的（点一下就入账），
   * 现在统一改成弹窗：赚钱类任务必须拍一张照片（或从相册选）才能提交。
   * custom 传进来是为了提交成功后标「今天做过」（内置任务传 null）。
   */
  const openCheckIn = (task: TaskConfig, custom: CustomTask | null = null) => {
    modalCustomTaskRef.current = custom;
    setActiveTask(task);
  };

  /**
   * 提交自定义任务 —— 需求 5：**「添加任务」这个动作本身不入账**，只写进任务列表。
   * 打卡完成时才写流水（孩子端首页的「我的任务」里点完成），所以这里绝不调 addLedgerRecord。
   */
  const handleCustomTask = (values: CustomTaskForm) => {
    const created = addCustomTask({
      name: values.name,
      value: values.value,
      type: values.type,
      createdBy: 'parent',
      // 表单里没渲染这个开关（消费 / 罚款）时给 undefined，store 按类型兜底
      requirePhoto: values.requirePhoto,
    });
    form.resetFields();
    message.success(`「${created.name}」已加进快捷任务，点一下就能打卡`);
  };

  if (error) {
    return (
      <div className={styles.errorWrap}>
        <ErrorState description={error} onRetry={() => void reloadLedger()} />
        {retrying && (
          <div className={styles.retryingHint}>
            <Spin size="small" /> 正在重试…
          </div>
        )}
      </div>
    );
  }

  if (loading && records.length === 0) {
    return <PageLoading />;
  }

  const isPositive = balance >= 0;
  const balanceColor = isPositive ? designTokens.colors.success : designTokens.colors.danger;

  /** 兑换区：输入积分数 → 按 100 积分 = 10 元折算成现金（没填视为 0，按钮同时禁用） */
  const exchangeValue = exchangePoints ?? 0;
  const exchangeYuan = pointsToYuan(exchangeValue);
  const canExchange = exchangeValue > 0 && exchangeValue <= balance;

  /** 格式化流水时间 */
  const formatTime = (iso: string) => {
    const d = new Date(iso);
    const nowD = new Date();
    const sameDay = d.toDateString() === nowD.toDateString();
    const time = d.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' });
    return sameDay ? `今天 ${time}` : `${d.getMonth() + 1}/${d.getDate()} ${time}`;
  };

  /** 审批通过：按条记 pending，连点不会重复提交（审批写操作不可重入） */
  const handleApprove = async (id: string) => {
    if (approvingIds.has(id)) return;
    setApprovingIds((prev) => new Set(prev).add(id));
    try {
      await approve(id);
      message.success('已审批通过，积分已入账');
    } catch (e) {
      message.error('操作失败，请重试');
    } finally {
      setApprovingIds((prev) => {
        const next = new Set(prev);
        next.delete(id);
        return next;
      });
    }
  };

  /** 审批驳回：先让家长写一句原因，这句话会进女儿的通知 */
  const handleReject = async () => {
    if (!rejectTarget) return;
    setRejecting(true);
    try {
      await reject(rejectTarget.id, rejectReason.trim() || undefined);
      message.success('已驳回，女儿会看到你的话');
      setRejectTarget(null);
      setRejectReason('');
    } catch (e) {
      message.error('操作失败，请重试');
    } finally {
      setRejecting(false);
    }
  };

  /** 批量通过：一次把待审批全部入账（孩子一口气交好几条时最省事） */
  const handleApproveAll = async () => {
    setApprovingAll(true);
    try {
      await approveMany(pendingRecords.map((r) => r.id));
      message.success(`已通过 ${pendingRecords.length} 条`);
    } catch (e) {
      message.error(e instanceof Error ? e.message : '操作失败，请重试');
    } finally {
      setApprovingAll(false);
    }
  };

  /** 驳回后重新提交 */
  const handleResubmit = async (id: string) => {
    try {
      await resubmitRequest(id);
      await loadLedger();
      message.success('已重新提交，等待家长审批');
    } catch (e) {
      message.error('操作失败，请重试');
    }
  };

  /** 小孩撤回自己还没被审批的申请（删掉记录，不再占用今日次数） */
  const handleWithdraw = async (id: string) => {
    try {
      await removeRecord(id);
      message.success('已撤回该申请');
    } catch (e) {
      message.error('撤回失败，请重试');
    }
  };

  /** 删除流水（仅家长），含图片时后端会一并删除 R2 中的图片 */
  const handleDelete = async (id: string) => {
    try {
      await removeRecord(id);
      message.success('已删除该记录');
    } catch (e) {
      message.error('删除失败，请重试');
    }
  };

  /**
   * 兑换现金（仅家长）：把指定积分数按 100 积分 = 10 元换成钱，记一条「现金兑现」支出。
   * 可以只兑换一部分（剩下的积分留在账上）；积分→钱的闭环留在同一本流水里，家长和孩子都能看到。
   */
  const handleSettle = async (points: number) => {
    const amount = Math.floor(points);
    if (amount <= 0 || amount > balance) return;
    setSettling(true);
    const yuan = pointsToYuan(amount);
    try {
      const task: TaskConfig = {
        id: 'payout',
        name: '现金兑现',
        type: 'spending',
        value: -amount,
        unit: '积分',
      };
      await addLedgerRecord(
        task,
        { note: `积分兑换现金：${amount} 积分 = ${yuan} 元` },
        { autoApprove: true }
      );
      await loadLedger();
      setExchangePoints(null);
      setSettleOpen(false);
      message.success(`已兑换 ${yuan} 元，扣掉 ${amount} 积分`);
    } catch (e) {
      // 账记上了但自动审批失败：积分没扣掉，那笔在待审批里 —— 不能说「已兑换」
      if (e instanceof LedgerApprovalError) {
        await loadLedger().catch(() => undefined);
        // 弹窗也关掉、输入清空：这一笔已经记上了，留在那儿再点一次会重复记账
        setExchangePoints(null);
        setSettleOpen(false);
        message.warning(`已记账，但审批没成功 —— ${amount} 积分还没扣掉，记录在待审批里，去点一下通过`);
      } else {
        message.error(e instanceof Error ? e.message : '兑换失败，请重试');
      }
    } finally {
      setSettling(false);
    }
  };

  /** 导出 CSV（仅家长）：按当前筛选导出全部记录（导出实现在 utils/exportLedger，首页也用同一份） */
  const handleExportCsv = () => {
    message.success(`已导出 ${exportLedgerCsv(filteredRecords)} 条记录`);
  };

  /** 流水状态标签 */
  const renderStatusTag = (record: LedgerRecord) => {
    const status = record.status;
    if (status === 'pending') {
      return <Tag color="processing">待审批</Tag>;
    }
    if (status === 'rejected') {
      return <Tag color="error">已驳回</Tag>;
    }
    return <Tag color="success">已入账</Tag>;
  };

  /** 一条快捷任务按钮（内置 / 自定义共用；done=true 的收在「今日已完成」里） */
  const renderTaskButton = (entry: TaskEntry) => {
    const earning = entry.task.value > 0;
    return (
      <Button
        key={entry.key}
        type={earning ? 'primary' : 'default'}
        danger={!earning}
        className={`${styles.actionBtn} btn-press`}
        // 已完成的按钮不再上色：交给 antd 的禁用样式变灰，一眼能看出这条做过了
        style={
          earning && !entry.done
            ? { background: designTokens.colors.success, borderColor: designTokens.colors.success }
            : undefined
        }
        icon={entry.done ? <CheckCircleOutlined /> : earning ? <PlusOutlined /> : <MinusOutlined />}
        disabled={entry.done}
        onClick={() => openCheckIn(entry.task, entry.custom)}
      >
        <span className={styles.actionBtnText}>{entry.task.name}</span>
        <span className={`num ${styles.actionBtnValue}`}>
          {entry.task.value > 0 ? `+${entry.task.value}` : entry.task.value}
        </span>
      </Button>
    );
  };

  /** 任务区内容 */
  const renderTasks = () => (
    <div className={styles.tasksArea}>
      {/* 快捷任务：只摊开今天还没做完的；做完的收进下面「今日已完成」 */}
      <div className={styles.actionSection}>
        <div className={styles.actionTitle}>快捷任务</div>
        <div className={styles.actionGrid}>
          {/* 赚钱任务 */}
          <div className={styles.actionGroup}>
            <div className={styles.actionGroupLabel}>
              <RiseOutlined /> 赚钱任务
            </div>
            {earningEntries.filter((entry) => !entry.done).map(renderTaskButton)}
            {earningEntries.every((entry) => entry.done) && (
              <div className={styles.groupAllDone}>今天的都做完啦</div>
            )}
          </div>
          {/* 消费/罚款 */}
          <div className={styles.actionGroup}>
            <div className={styles.actionGroupLabel}>
              <FallOutlined /> 消费 / 罚款
            </div>
            {spendingEntries.filter((entry) => !entry.done).map(renderTaskButton)}
            {spendingEntries.every((entry) => entry.done) && (
              <div className={styles.groupAllDone}>今天的都记完啦</div>
            )}
          </div>
        </div>

        {/* 已完成折叠：默认收起 —— 打过卡的任务不该继续占着屏幕 */}
        {doneEntries.length > 0 && (
          <div className={styles.doneBlock}>
            <Button
              type="text"
              block
              className={styles.doneToggle}
              onClick={() => setShowDoneTasks((open) => !open)}
              aria-expanded={showDoneTasks}
            >
              <span className={styles.toggleInner}>
                <CheckCircleOutlined />
                <span>今日已完成 {doneEntries.length} 项</span>
                {showDoneTasks ? <UpOutlined /> : <DownOutlined />}
              </span>
            </Button>
            {showDoneTasks && <div className={styles.doneList}>{doneEntries.map(renderTaskButton)}</div>}
          </div>
        )}
      </div>

      {/* 自定义任务（仅家长：任务由家长定义，小孩只需打卡） */}
      {isParent && (
        <Card className={styles.customCard} variant="borderless">
          {/* 管理区默认收起：表单和任务清单不该天天占着任务区的下半屏 */}
          <Button
            type="text"
            block
            className={styles.customToggle}
            onClick={() => setShowCustomManager((open) => !open)}
            aria-expanded={showCustomManager}
          >
            <span className={styles.toggleInner}>
              <PlusOutlined />
              <span>{customTasks.length > 0 ? `自定义任务 · ${customTasks.length} 个` : '自定义任务'}</span>
              {showCustomManager ? <UpOutlined /> : <DownOutlined />}
            </span>
          </Button>
          {showCustomManager && (
          <>
          <Form form={form} layout="vertical" onFinish={handleCustomTask} className={styles.customForm}>
            <div className={styles.customRow}>
              <Form.Item name="type" label="类型" rules={[{ required: true, message: '请选择类型' }]}>
                <Select
                  placeholder="选择类型"
                  options={[
                    { value: 'earning', label: '赚钱' },
                    { value: 'spending', label: '消费 / 罚款' },
                  ]}
                />
              </Form.Item>
              <Form.Item name="value" label="价格" rules={[{ required: true, message: '请输入价格' }]}>
                <InputNumber min={1} placeholder="积分" style={{ width: '100%' }} />
              </Form.Item>
            </div>
            <Form.Item name="name" label="名称" rules={[{ required: true, message: '请输入任务名称' }]}>
              <Input placeholder="例如：帮忙浇花" maxLength={20} />
            </Form.Item>
            {/* 照片要求：需求「添加自定义任务里加一个选项，是否必须添加照片」。
                默认开启 —— 孩子交的任务大多得看见东西才算数；消费 / 罚款只要写清原因，不需要照片。 */}
            {customFormType === 'earning' && (
              <Form.Item
                name="requirePhoto"
                label="必须添加照片"
                valuePropName="checked"
                initialValue={true}
                extra="开启后，提交这条任务要先拍照或从相册选一张照片；关闭则可以直接提交"
              >
                <Switch />
              </Form.Item>
            )}
            <Button type="primary" htmlType="submit" block className={styles.customSubmit}>
              添加任务
            </Button>
          </Form>
          {/* 任务列表（本地存档）：添加进来的任务都在这里，打卡完成才给积分（需求 5） */}
          <List
            size="small"
            style={{ marginTop: 12 }}
            dataSource={customTasks}
            locale={{ emptyText: '还没有任务，添加一个吧' }}
            renderItem={(task) => (
              <List.Item
                actions={[
                  <Popconfirm
                    key="delete"
                    title="删掉这个任务？"
                    okText="删掉"
                    cancelText="取消"
                    onConfirm={() => removeCustomTask(task.id)}
                  >
                    <Button
                      type="text"
                      size="small"
                      danger
                      icon={<DeleteOutlined />}
                      aria-label="删除任务"
                    />
                  </Popconfirm>,
                ]}
              >
                <span style={{ marginRight: 8 }}>{task.name}</span>
                <Tag color={task.kind === 'preset' ? 'blue' : task.createdBy === 'child' ? 'orange' : 'default'}>
                  {task.kind === 'preset' ? '预置' : task.createdBy === 'child' ? '孩子提的' : '自定义'}
                </Tag>
                {/* 要照片的任务标出来：家长一眼能看出哪几条孩子得拍照才能交 */}
                {task.requirePhoto && (
                  <Tag icon={<CameraOutlined />} color="purple">
                    需照片
                  </Tag>
                )}
                <span
                  className="num"
                  style={{
                    marginLeft: 8,
                    fontWeight: 600,
                    color:
                      task.value > 0 ? designTokens.colors.success : designTokens.colors.danger,
                  }}
                >
                  {task.value > 0 ? `+${task.value}` : task.value}
                </span>
              </List.Item>
            )}
          />
          </>
          )}
        </Card>
      )}
    </div>
  );

  /** 一条流水（按天分组后组头已经给了当天小计，条目只留必要信息） */
  const renderRecordRow = (record: LedgerRecord) => (
    <li key={record.id} className={styles.recordRow}>
      <div
        className={styles.recordIcon}
        style={{
          background: record.amount >= 0 ? 'rgba(15, 155, 108, 0.12)' : 'rgba(233, 69, 96, 0.12)',
          color: record.amount >= 0 ? designTokens.colors.success : designTokens.colors.danger,
        }}
      >
        {record.amount >= 0 ? <RiseOutlined /> : <FallOutlined />}
      </div>
      <div className={styles.recordMain}>
        <div className={styles.recordTitle}>{record.task_name}</div>
        {/* 时间与备注并作一行：原来备注单独占一行，条目被撑得很高 */}
        <div className={styles.recordSub}>
          {formatTime(record.created_at)}
          {record.note ? ` · ${record.note}` : ''}
        </div>
      </div>
      <div className={styles.recordRight}>
        <span className={styles.recordTop}>
          <span
            className={`num ${styles.recordAmount}`}
            style={{
              color: record.amount >= 0 ? designTokens.colors.success : designTokens.colors.danger,
            }}
          >
            {record.amount >= 0 ? '+' : ''}
            {record.amount}
          </span>
          {/* 审批状态 */}
          {renderStatusTag(record)}
        </span>
        {/* 图片缩略图（点击查看大图） */}
        {record.image_url && (
          <Image
            src={record.image_url}
            alt={record.task_name}
            width={44}
            height={44}
            className={styles.recordImage}
            preview={{ mask: <EyeOutlined /> }}
          />
        )}
        {/* 小孩撤回自己待审批的申请 */}
        {!isParent && record.status === 'pending' && (
          <Popconfirm
            title="撤回这条申请？"
            description="撤回后记录会被删除，可以重新打卡"
            okText="撤回"
            cancelText="取消"
            onConfirm={() => handleWithdraw(record.id)}
          >
            <Button size="small" icon={<RollbackOutlined />} className={styles.resubmitBtn}>
              撤回
            </Button>
          </Popconfirm>
        )}
        {/* 驳回后重新提交：这是孩子对自己申请的补救动作 —— 家长端不给这个按钮，
            只留一句只读说明（家长看到「重新提交」也会以为该由自己点） */}
        {!isParent && record.status === 'rejected' && (
          <Button size="small" className={styles.resubmitBtn} onClick={() => handleResubmit(record.id)}>
            重新提交
          </Button>
        )}
        {isParent && record.status === 'rejected' && (
          <span className={styles.rejectedNote}>已驳回 · 孩子可重新提交</span>
        )}
        {/* 删除（仅家长）：含图片时后端一并删除 R2 图片 */}
        {isParent && (
          <Popconfirm
            title="确认删除该记录？"
            description={record.image_url ? '关联图片也会一并删除，且不可恢复' : '删除后不可恢复'}
            okText="删除"
            okButtonProps={{ danger: true }}
            cancelText="取消"
            onConfirm={() => handleDelete(record.id)}
          >
            <Button size="small" danger icon={<DeleteOutlined />} className={styles.resubmitBtn}>
              删除
            </Button>
          </Popconfirm>
        )}
      </div>
    </li>
  );

  /** 历史记录区内容：按天分组（组头给净额小计），条目挂在每天下面 */
  const renderRecords = () => (
    <Card className={styles.recordsCard} variant="borderless">
      {/* 状态筛选 + 导出（导出仅家长） */}
      <div className={styles.recordToolbar}>
        <Segmented
          size="small"
          value={recordFilter}
          onChange={(value) => setRecordFilter(value as RecordFilter)}
          options={[
            { label: '全部', value: 'all' },
            { label: '待审批', value: 'pending' },
            { label: '已入账', value: 'approved' },
            { label: '已驳回', value: 'rejected' },
          ]}
        />
        {isParent && filteredRecords.length > 0 && (
          <Button size="small" icon={<DownloadOutlined />} onClick={handleExportCsv}>
            导出 CSV
          </Button>
        )}
      </div>

      {filteredRecords.length === 0 ? (
        <EmptyState description={recordFilter === 'all' ? '暂无流水记录' : '该状态下暂无记录'} />
      ) : (
        <>
          <div className={styles.dayList}>
            {visibleGroups.map((group) => (
              <section key={group.key} className={styles.dayGroup}>
                <div className={styles.dayHead}>
                  <span className={styles.dayLabel}>{group.label}</span>
                  <span className={styles.dayMeta}>
                    {group.pendingCount > 0 && (
                      <span className={styles.dayPending}>{group.pendingCount} 条待审批</span>
                    )}
                    {group.net !== 0 && (
                      <span
                        className={`num ${styles.dayNet}`}
                        style={{
                          color: group.net > 0 ? designTokens.colors.success : designTokens.colors.danger,
                        }}
                      >
                        {group.net > 0 ? '+' : ''}
                        {group.net}
                      </span>
                    )}
                  </span>
                </div>
                <ul className={styles.recordList}>{group.records.map(renderRecordRow)}</ul>
              </section>
            ))}
          </div>
          {/* 按天分页：一次 7 天，点一次多 7 天（同一天不会被切成两段） */}
          {hiddenDayCount > 0 && (
            <Button
              block
              type="dashed"
              className={styles.loadMore}
              onClick={() => setVisibleDays((days) => days + RECORDS_PAGE_DAYS)}
            >
              加载更多（还有 {hiddenDayCount} 天）
            </Button>
          )}
        </>
      )}
    </Card>
  );

  /** 待审批区内容（仅家长可见） */
  const renderPending = () => (
    <Card className={styles.recordsCard} variant="borderless">
      {pendingRecords.length === 0 ? (
        <EmptyState description="暂无待审批申请" />
      ) : (
        <>
          <div className={styles.pendingHead}>
            <span className={styles.pendingCount}>共 {pendingRecords.length} 条待审批</span>
            <Popconfirm
              title={`一次通过全部 ${pendingRecords.length} 条？`}
              description="确认后才入账；要驳回的请单独处理"
              okText="全部通过"
              cancelText="再想想"
              onConfirm={handleApproveAll}
            >
              <Button size="small" type="primary" loading={approvingAll} icon={<CheckCircleOutlined />}>
                全部通过
              </Button>
            </Popconfirm>
          </div>
          <List
          dataSource={pendingRecords}
          renderItem={(record) => (
            <List.Item className={styles.pendingItem}>
              <List.Item.Meta
                avatar={
                  <div
                    className={styles.recordIcon}
                    style={{
                      background: 'rgba(22, 119, 255, 0.12)',
                      color: designTokens.colors.primary,
                    }}
                  >
                    <AuditOutlined />
                  </div>
                }
                title={record.task_name}
                description={formatTime(record.created_at)}
              />
              <div className={styles.recordRight}>
                <span
                  className={`num ${styles.recordAmount}`}
                  style={{
                    color: record.amount >= 0 ? designTokens.colors.success : designTokens.colors.danger,
                  }}
                >
                  {record.amount >= 0 ? '+' : ''}
                  {record.amount}
                </span>
                {record.note && <div className={styles.pendingNote}>{record.note}</div>}
                {record.image_url && (
                  <Image
                    src={record.image_url}
                    alt={record.task_name}
                    width={48}
                    height={48}
                    className={styles.recordImage}
                    preview={{ mask: <EyeOutlined /> }}
                  />
                )}
                <div className={styles.approveActions}>
                  <Button
                    size="small"
                    type="primary"
                    className={styles.approveBtn}
                    style={{
                      background: record.amount >= 0 ? designTokens.colors.success : designTokens.colors.danger,
                      borderColor: record.amount >= 0 ? designTokens.colors.success : designTokens.colors.danger,
                    }}
                    icon={<CheckCircleOutlined />}
                    loading={approvingIds.has(record.id)}
                    onClick={() => handleApprove(record.id)}
                  >
                    通过
                  </Button>
                  <Button
                    size="small"
                    icon={<CloseCircleOutlined />}
                    onClick={() => {
                      setRejectTarget(record);
                      setRejectReason('');
                    }}
                  >
                    驳回
                  </Button>
                </div>
              </div>
            </List.Item>
          )}
        />
        </>
      )}
    </Card>
  );

  return (
    <div className={styles.dashboard}>
      {/* ===== 左侧：积分银行 + Tab 切换 ===== */}
      <div className={styles.leftCol}>
        {/* 余额大卡片 */}
        <Card className={styles.balanceCard} variant="borderless">
          <div className={styles.balanceHeader}>
            <span className={styles.balanceLabel}>
              <WalletOutlined /> 当前总积分
            </span>
            <Tag
              color={isPositive ? 'success' : 'error'}
              className={styles.balanceTrend}
              icon={isPositive ? <RiseOutlined /> : <FallOutlined />}
            >
              {isPositive ? '盈余' : '透支'}
            </Tag>
          </div>
          <div className={`num ${styles.balanceValue}`} style={{ color: balanceColor }}>
            {balance}
          </div>
          <div className={styles.balanceSub}>可用积分</div>
          {isParent && pendingCount > 0 && (
            // 点一下就跳到「待审批」页签处理，不用家长自己去翻
            <button type="button" className={styles.pendingHint} onClick={() => setActiveTab('pending')}>
              <AuditOutlined /> 待审批 {pendingCount} 项
            </button>
          )}
          {/* 兑现入口：余额卡只留一个按钮，填写与确认都挪进弹窗（见文件末尾的 Modal） */}
          {isParent && balance > 0 && (
            <Button
              className={styles.settleEntry}
              icon={<WalletOutlined />}
              onClick={() => setSettleOpen(true)}
            >
              兑现现金
            </Button>
          )}
        </Card>

        {/* Tab 切换：任务区 / 历史记录区 */}
        <Tabs
          activeKey={visibleTab}
          onChange={setActiveTab}
          className={styles.tabs}
          items={[
            {
              key: 'tasks',
              label: (
                <span className={styles.tabLabel}>
                  <AppstoreOutlined /> 任务区
                </span>
              ),
              children: renderTasks(),
            },
            // 家长端：待审批 Tab（带数量角标）
            ...(isParent
              ? [
                  {
                    key: 'pending',
                    label: (
                      <span className={styles.tabLabel}>
                        <AuditOutlined /> 待审批
                        {pendingCount > 0 && <Badge count={pendingCount} size="small" offset={[6, -2]} />}
                      </span>
                    ),
                    children: renderPending(),
                  },
                ]
              : []),
            {
              key: 'records',
              label: (
                <span className={styles.tabLabel}>
                  <HistoryOutlined /> 历史记录
                </span>
              ),
              children: renderRecords(),
            },
          ]}
        />
      </div>

      {/* ===== 右侧：今日任务与作息 + 趋势图 ===== */}
      <div className={styles.rightCol}>
        <Card className={styles.todayCard} variant="borderless">
          <div className={styles.todayTitle}>
            <ClockCircleOutlined /> 今日任务与作息
          </div>
          <div className={`num ${styles.clock}`}>
            {now.toLocaleTimeString('zh-CN', { hour12: false })}
          </div>
          <div className={styles.dateText}>
            {now.toLocaleDateString('zh-CN', { month: 'long', day: 'numeric', weekday: 'long' })}
          </div>

          {isLate ? (
            <div className={styles.lateWarning}>
              <Tag color="error" icon={<MoonOutlined />}>
                已过 22:00，未打卡睡觉会记一次罚款
              </Tag>
            </div>
          ) : (
            <div className={styles.lateOk}>
              <Tag color="success" icon={<CheckCircleOutlined />}>
                作息正常
              </Tag>
            </div>
          )}

          <div className={styles.quickActions}>
            <Button
              type="primary"
              className={`${styles.quickBtn} btn-press`}
              style={{
                background: designTokens.colors.success,
                borderColor: designTokens.colors.success,
              }}
              icon={<CheckCircleOutlined />}
              disabled={!homeworkTask || isDone(homeworkTask)}
              onClick={() => homeworkTask && openCheckIn(homeworkTask)}
            >
              按时完成作业
            </Button>
            <Button
              type="primary"
              className={`${styles.quickBtn} btn-press`}
              style={{
                background: designTokens.colors.primary,
                borderColor: designTokens.colors.primary,
              }}
              icon={<MoonOutlined />}
              disabled={!sleepTask || isDone(sleepTask)}
              onClick={() => sleepTask && openCheckIn(sleepTask)}
            >
              按时睡觉
            </Button>
          </div>
        </Card>

        {/* 近 14 天积分趋势（echarts 按需引入，见 components/BalanceTrend.tsx） */}
        <div className={styles.trendWrap}>
          <BalanceTrend records={records} />
        </div>
      </div>

      {/* ===== 驳回弹窗：写一句话给女儿，而不是点一下就走 ===== */}
      <Modal
        open={!!rejectTarget}
        title={rejectTarget ? `驳回「${rejectTarget.task_name}」` : ''}
        okText="确认驳回"
        cancelText="取消"
        okButtonProps={{ danger: true }}
        confirmLoading={rejecting}
        onOk={handleReject}
        onCancel={() => {
          setRejectTarget(null);
          setRejectReason('');
        }}
        destroyOnHidden
      >
        <p className={styles.rejectHint}>
          写一句为什么不行 —— 女儿会收到这句话；不写的话她只看到「已驳回」。
        </p>
        <Input.TextArea
          value={rejectReason}
          onChange={(e) => setRejectReason(e.target.value)}
          placeholder="例如：照片看不清，重新拍一张"
          rows={3}
          maxLength={60}
          showCount
        />
      </Modal>

      {/* ===== 兑现弹窗：余额卡上只留一个入口，填写与确认都在这里 ===== */}
      <Modal
        open={settleOpen}
        title="积分兑换现金"
        okText={canExchange ? `兑换 ${exchangeYuan} 元` : '兑换'}
        cancelText="取消"
        okButtonProps={{ disabled: !canExchange }}
        confirmLoading={settling}
        onOk={() => void handleSettle(exchangeValue)}
        onCancel={() => setSettleOpen(false)}
        destroyOnHidden
      >
        <p className={styles.exchangeHint}>
          汇率 {EXCHANGE_RATE_TEXT}，可以只兑现一部分，剩下的积分留在账上；兑换会记一条「现金兑现」支出，
          需要回退就到历史记录里删掉那条。
        </p>
        <InputNumber
          className={styles.exchangeInput}
          min={1}
          max={balance}
          precision={0}
          value={exchangePoints}
          onChange={(v) => setExchangePoints(typeof v === 'number' ? v : null)}
          placeholder={`想兑换多少积分（最多 ${balance}）`}
          addonAfter="积分"
        />
        <div className={styles.exchangeTip}>
          将兑换 <span className="num">{exchangeValue}</span> 积分 ={' '}
          <span className="num">{exchangeYuan}</span> 元
        </div>
      </Modal>

      {/* ===== 任务打卡弹窗（照片与备注草稿由组件内部管理） ===== */}
      <CheckInModal
        task={activeTask}
        isParent={isParent}
        guard={guardTask}
        onClose={() => setActiveTask(null)}
        onSuccess={async (task, recordId) => {
          // 从自定义任务按钮进来的：把那条标成「今天做过」，按钮立刻置灰（服务端还会再判一次重）
          const custom = modalCustomTaskRef.current;
          if (custom) markTaskDone(custom.id);
          modalCustomTaskRef.current = null;
          await loadLedger();
          notifySuccess(task, recordId);
        }}
      />
    </div>
  );
}
