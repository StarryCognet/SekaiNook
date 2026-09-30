import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Button, Card, List, Tag, Tabs, Form, Input, Select, InputNumber, Image, message, Badge, Popconfirm, Segmented, Modal, Spin } from 'antd';
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
} from '@ant-design/icons';
import { addLedgerRecord, LedgerApprovalError, resubmitRequest } from '../../api/familyLedger';
import { useViewState } from '../../utils/useViewState';
import { exportLedgerCsv } from '../../utils/exportLedger';
import { checkTask, isTaskDone } from '../../utils/taskRules';
import { getTasksByType } from '../../config/familyRules';
import { useFamilyStore } from '../../store/useFamilyStore';
import { PageLoading, EmptyState, ErrorState } from '../../components/StateViews';
import BalanceTrend from '../../components/BalanceTrend';
import CheckInModal from '../../components/CheckInModal';
import { designTokens } from '../../theme/tokens';
import type { LedgerRecord, LedgerStatus, TaskConfig, TaskType } from '../../types/family';
import styles from './FamilyDashboard.module.css';

/** 历史记录每页条数（手机端长列表一次性渲染会卡，改为「加载更多」分页） */
const RECORDS_PAGE_SIZE = 20;

/** 历史记录状态筛选值：全部 / 待审批 / 已入账 / 已驳回 */
type RecordFilter = 'all' | LedgerStatus;

/** 自定义任务表单值 */
interface CustomTaskForm {
  type: TaskType;
  name: string;
  value: number;
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
  /** 驳回弹窗：正在驳回哪一条 + 家长写给孩子的那句话 */
  const [rejectTarget, setRejectTarget] = useState<LedgerRecord | null>(null);
  const [rejectReason, setRejectReason] = useState('');
  const [rejecting, setRejecting] = useState(false);
  const [approvingAll, setApprovingAll] = useState(false);
  /** 正在审批的记录 id（按条加 loading，防止连点重复提交） */
  const [approvingIds, setApprovingIds] = useState<ReadonlySet<string>>(() => new Set());

  const isParent = role === 'parent';

  /**
   * 「待审批」Tab 只对家长存在，而 activeTab 是按 key 记的（跨身份共用同一份存储）。
   * 家长停在待审批、切回小孩身份再进账本时，activeKey 指向一个不存在的 Tab，内容区就是空白。
   * 这里让小孩端回落到任务区：不动存储 key —— KidHome.tsx / ParentHome.tsx 也在写 family.activeTab，
   * 改 key 得同时改清单外的文件，漏一个就写错地方；家长原来的选择也照样留着。
   */
  const visibleTab = !isParent && activeTab === 'pending' ? 'tasks' : activeTab;

  // 任务打卡弹窗状态（照片与备注草稿由 CheckInModal 自己管）
  const [activeTask, setActiveTask] = useState<TaskConfig | null>(null);
  /** 正在提交的任务 id（防止手机连点重复入账） */
  const [submittingId, setSubmittingId] = useState<string | null>(null);
  /** 正在结算兑现（家长） */
  const [settling, setSettling] = useState(false);
  /** 历史记录状态筛选 + 已渲染条数（分页）—— 跨页面切换保留，切走再回来还是原样 */
  const [recordFilter, setRecordFilter] = useViewState<RecordFilter>('family.recordFilter', 'all');
  const [visibleCount, setVisibleCount] = useViewState<number>('family.visibleCount', RECORDS_PAGE_SIZE);
  /** 首次挂载不算「切换筛选」，否则会把恢复出来的分页进度清零 */
  const filterMountedRef = useRef(false);

  const earningTasks = getTasksByType('earning');
  const spendingTasks = getTasksByType('spending');
  /** 右侧快捷按钮对应的任务（可能不存在，避免用非空断言） */
  const homeworkTask = earningTasks.find((t) => t.id === 'finish_homework');
  const sleepTask = earningTasks.find((t) => t.id === 'sleep_on_time');

  /** 历史记录：按状态筛选（all = 全部） */
  const filteredRecords = useMemo(
    () => (recordFilter === 'all' ? records : records.filter((r) => (r.status ?? 'approved') === recordFilter)),
    [records, recordFilter]
  );

  /** 当前已渲染的历史记录（加载更多分页） */
  const visibleRecords = useMemo(
    () => filteredRecords.slice(0, visibleCount),
    [filteredRecords, visibleCount]
  );

  /**
   * 拉账本：**成功才清掉 error** —— 以前全文件没有 setError(null)，
   * 点「重试」就算成功也会一直停在错误页。重试期间用 retrying 给出反馈。
   */
  const reloadLedger = useCallback(async () => {
    setRetrying(true);
    try {
      await loadLedger();
      setError(null);
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
    setVisibleCount(RECORDS_PAGE_SIZE);
  }, [recordFilter, setVisibleCount]);

  // 每秒刷新当前时间（用于作息判断）
  useEffect(() => {
    const timer = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(timer);
  }, []);

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
  const isLate = hour >= 21;

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
   * 记账失败的处理：`LedgerApprovalError` 表示账已经记上了、只是自动审批那一步没成功 ——
   * 这笔钱并没有入账，记录正以 pending 躺在待审批里。这里重新拉一次账本让那条 pending
   * 真的显示出来，并明确告诉家长去点「通过」；绝不能再报成成功。
   */
  const handleWriteError = async (e: unknown, fallback: string) => {
    if (e instanceof LedgerApprovalError) {
      await loadLedger().catch(() => undefined);
      message.warning(e.message);
      return;
    }
    message.error(e instanceof Error ? e.message : fallback);
  };

  /** 打卡：写入流水（小孩端为待审批申请）并刷新余额 */
  const handleTask = async (task: TaskConfig) => {
    const blocked = guardTask(task);
    if (blocked) {
      message.warning(blocked);
      return;
    }
    if (submittingId) return; // 提交中忽略重复点击
    setSubmittingId(task.id);
    try {
      const recordId = await addLedgerRecord(
        task,
        undefined,
        // 家长自己记的账让服务端立刻入账，女儿提交的一律进待审批
        { autoApprove: isParent }
      );
      await loadLedger();
      notifySuccess(task, recordId);
    } catch (e) {
      await handleWriteError(e, '操作失败，请重试');
    } finally {
      setSubmittingId(null);
    }
  };

  /** 提交自定义任务 */
  const handleCustomTask = async (values: CustomTaskForm) => {
    const task: TaskConfig = {
      id: `custom_${Date.now()}`,
      name: values.name.trim(),
      type: values.type,
      value: values.type === 'earning' ? Math.abs(values.value) : -Math.abs(values.value),
      unit: '积分',
    };
    try {
      const recordId = await addLedgerRecord(
        task,
        undefined,
        { autoApprove: isParent }
      );
      await loadLedger();
      form.resetFields();
      notifySuccess(task, recordId);
    } catch (e) {
      await handleWriteError(e, '添加失败，请重试');
    }
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
   * 结算兑现（仅家长）：把当前余额记成一条「现金兑现」支出，余额随之清零。
   * 这样积分→钱的闭环留在同一本流水里，家长和孩子都能看到兑现记录。
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
      await addLedgerRecord(
        task,
        { note: '结算兑现，余额清零' },
        { autoApprove: true }
      );
      await loadLedger();
      message.success(`已兑现 ${amount} 积分，余额清零`);
    } catch (e) {
      // 账记上了但自动审批失败：钱没清零，那笔在待审批里 —— 不能说「余额清零」
      if (e instanceof LedgerApprovalError) {
        await loadLedger().catch(() => undefined);
        message.warning(`已记账，但审批没成功 —— ${amount} 积分还没清零，记录在待审批里，去点一下通过`);
      } else {
        message.error(e instanceof Error ? e.message : '结算失败，请重试');
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

  /** 任务区内容 */
  const renderTasks = () => (
    <div className={styles.tasksArea}>
      {/* 快捷任务 */}
      <div className={styles.actionSection}>
        <div className={styles.actionTitle}>快捷任务</div>
        <div className={styles.actionGrid}>
          {/* 赚钱任务 */}
          <div className={styles.actionGroup}>
            <div className={styles.actionGroupLabel}>
              <RiseOutlined /> 赚钱任务
            </div>
            {earningTasks.map((task) => (
              <Button
                key={task.id}
                type="primary"
                className={`${styles.actionBtn} btn-press`}
                style={{
                  background: designTokens.colors.success,
                  borderColor: designTokens.colors.success,
                }}
                icon={<PlusOutlined />}
                disabled={isDone(task)}
                onClick={() => setActiveTask(task)}
              >
                <span className={styles.actionBtnText}>{task.name}</span>
                <span className={`num ${styles.actionBtnValue}`}>+{task.value}</span>
              </Button>
            ))}
          </div>
          {/* 消费/罚款 */}
          <div className={styles.actionGroup}>
            <div className={styles.actionGroupLabel}>
              <FallOutlined /> 消费 / 罚款
            </div>
            {spendingTasks.map((task) => (
              <Button
                key={task.id}
                danger
                className={`${styles.actionBtn} btn-press`}
                icon={<MinusOutlined />}
                disabled={isDone(task)}
                onClick={() => setActiveTask(task)}
              >
                <span className={styles.actionBtnText}>{task.name}</span>
                <span className={`num ${styles.actionBtnValue}`}>{task.value}</span>
              </Button>
            ))}
          </div>
        </div>
      </div>

      {/* 自定义任务（仅家长：任务由家长定义，小孩只需打卡） */}
      {isParent && (
        <Card className={styles.customCard} variant="borderless">
          <div className={styles.customTitle}>
            <PlusOutlined /> 自定义任务
          </div>
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
            <Button type="primary" htmlType="submit" block className={styles.customSubmit}>
              添加任务
            </Button>
          </Form>
        </Card>
      )}
    </div>
  );

  /** 历史记录区内容 */
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
          <List
            dataSource={visibleRecords}
            renderItem={(record) => (
              <List.Item className={styles.recordItem}>
                <List.Item.Meta
                  avatar={
                    <div
                      className={styles.recordIcon}
                      style={{
                        background:
                          record.amount >= 0
                            ? 'rgba(15, 155, 108, 0.12)'
                            : 'rgba(233, 69, 96, 0.12)',
                        color: record.amount >= 0 ? designTokens.colors.success : designTokens.colors.danger,
                      }}
                    >
                      {record.amount >= 0 ? <RiseOutlined /> : <FallOutlined />}
                    </div>
                  }
                  title={record.task_name}
                  description={formatTime(record.created_at)}
                />
                <div className={styles.recordRight}>
                  {/* 审批状态 */}
                  {renderStatusTag(record)}
                  <span
                    className={`num ${styles.recordAmount}`}
                    style={{
                      color: record.amount >= 0 ? designTokens.colors.success : designTokens.colors.danger,
                    }}
                  >
                    {record.amount >= 0 ? '+' : ''}
                    {record.amount}
                  </span>
                  {/* 备注 */}
                  {record.note && <div className={styles.recordNote}>{record.note}</div>}
                  {/* 图片缩略图（点击查看大图） */}
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
              </List.Item>
            )}
          />
          {/* 长列表分页：一次 20 条，点一次多 20 条 */}
          {filteredRecords.length > visibleRecords.length && (
            <Button
              block
              type="dashed"
              className={styles.loadMore}
              onClick={() => setVisibleCount((count) => count + RECORDS_PAGE_SIZE)}
            >
              加载更多（还有 {filteredRecords.length - visibleRecords.length} 条）
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
            <List.Item className={styles.recordItem}>
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
                {record.note && <div className={styles.recordNote}>{record.note}</div>}
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
          <div className={styles.balanceSub}>可用余额</div>
          {isParent && pendingCount > 0 && (
            <div className={styles.pendingHint}>
              <AuditOutlined /> 待审批 {pendingCount} 项
            </div>
          )}
          {/* 结算兑现：把余额换成现金，余额清零（仅家长、余额为正时） */}
          {isParent && balance > 0 && (
            <Popconfirm
              title={`兑现 ${balance} 积分？`}
              description="会记一条「现金兑现」支出，余额清零；如需回退请删除该记录"
              okText="确认兑现"
              cancelText="取消"
              onConfirm={handleSettle}
            >
              <Button className={styles.settleBtn} icon={<WalletOutlined />} loading={settling}>
                结算兑现（清零余额）
              </Button>
            </Popconfirm>
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
                注意作息，否则触发罚款
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
              loading={submittingId === homeworkTask?.id}
              onClick={() => homeworkTask && handleTask(homeworkTask)}
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
              loading={submittingId === sleepTask?.id}
              onClick={() => sleepTask && handleTask(sleepTask)}
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

      {/* ===== 任务打卡弹窗（照片与备注草稿由组件内部管理） ===== */}
      <CheckInModal
        task={activeTask}
        isParent={isParent}
        guard={guardTask}
        onClose={() => setActiveTask(null)}
        onSuccess={async (task, recordId) => {
          await loadLedger();
          notifySuccess(task, recordId);
        }}
      />
    </div>
  );
}
