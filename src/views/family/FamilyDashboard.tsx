import { useEffect, useMemo, useRef, useState } from 'react';
import { Button, Card, List, Tag, Tabs, Form, Input, Select, InputNumber, Modal, Image, message, Badge, Popconfirm, Segmented } from 'antd';
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
  CameraOutlined,
  PictureOutlined,
  EyeOutlined,
  AuditOutlined,
  CloseCircleOutlined,
  DeleteOutlined,
  RollbackOutlined,
  DownloadOutlined,
} from '@ant-design/icons';
import { addLedgerRecord, resubmitRequest } from '../../api/familyLedger';
import { uploadImage } from '../../api/upload';
import { compressImage } from '../../utils/image';
import { useBackButton } from '../../utils/useBackButton';
import { useViewState } from '../../utils/useViewState';
import { getTasksByType } from '../../config/familyRules';
import { useFamilyStore } from '../../store/useFamilyStore';
import { PageLoading, EmptyState, ErrorState } from '../../components/StateViews';
import BalanceTrend from '../../components/BalanceTrend';
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
    reject,
    removeRecord,
  } = useFamilyStore();
  const [error, setError] = useState<string | null>(null);
  const [now, setNow] = useState(new Date());
  // 当前分页（任务区 / 待审批 / 历史记录）—— 切到别的页面再回来要还在原来那页
  const [activeTab, setActiveTab] = useViewState('family.activeTab', 'tasks');
  const [form] = Form.useForm<CustomTaskForm>();

  const isParent = role === 'parent';

  // 任务打卡弹窗状态
  const [activeTask, setActiveTask] = useState<TaskConfig | null>(null);
  const [note, setNote] = useState('');
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
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

  // 初始化加载
  useEffect(() => {
    loadLedger().catch((e) => setError(e instanceof Error ? e.message : '加载失败'));
  }, [loadLedger]);

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

  /** 打开任务打卡弹窗 */
  const openTaskModal = (task: TaskConfig) => {
    setActiveTask(task);
    setNote('');
    setImageFile(null);
    setImagePreview(null);
  };

  /** 关闭任务打卡弹窗 */
  const closeTaskModal = () => {
    setActiveTask(null);
    setNote('');
    setImageFile(null);
    setImagePreview(null);
  };

  // 安卓硬件返回键：打卡弹窗打开时，返回键先关弹窗，而不是直接退出应用
  useBackButton(!!activeTask, closeTaskModal);

  /** 当天该任务已提交次数（含待审批，不含被驳回） */
  const countTodaySubmissions = (taskId: string): number => {
    const today = new Date().toDateString();
    return records.filter(
      (r) =>
        r.task_id === taskId &&
        r.status !== 'rejected' &&
        new Date(r.created_at).toDateString() === today
    ).length;
  };

  /** 任务能否打卡；不能时返回给用户看的提示文案 */
  const checkTask = (task: TaskConfig): string | null => {
    if (task.window) {
      const [startH, startM] = task.window.start.split(':').map(Number);
      const [endH, endM] = task.window.end.split(':').map(Number);
      const minutes = now.getHours() * 60 + now.getMinutes();
      if (minutes < startH * 60 + startM || minutes > endH * 60 + endM) {
        return `「${task.name}」只能在 ${task.window.start}-${task.window.end} 之间打卡`;
      }
    }
    if (task.dailyLimit !== undefined && countTodaySubmissions(task.id) >= task.dailyLimit) {
      return task.dailyLimit === 1
        ? `「${task.name}」今天已经打过卡啦`
        : `「${task.name}」每天最多 ${task.dailyLimit} 次，今天用完啦`;
    }
    return null;
  };

  /** 是否已达今日上限（按钮置灰，避免重复打卡） */
  const isTaskDone = (task: TaskConfig): boolean =>
    task.dailyLimit !== undefined && countTodaySubmissions(task.id) >= task.dailyLimit;

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

  /** 选择图片（拍照或相册） */
  const handleImageChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setImageFile(file);
    setImagePreview(URL.createObjectURL(file));
    e.target.value = '';
  };

  /** 提交任务打卡：压缩图片 → 上传（如有）→ 写入流水 */
  const handleTaskSubmit = async () => {
    if (!activeTask) return;
    const blocked = checkTask(activeTask);
    if (blocked) {
      message.warning(blocked);
      return;
    }

    setUploading(true);
    let imageUrl: string | undefined;
    let uploadError: string | null = null;

    // 上传图片（失败不阻断打卡，但必须把原因说清楚）
    if (imageFile) {
      try {
        // 手机原图常 3-15MB，先压到长边 1600 并转 JPEG，绕开后端 5MB 上限与 HEIF 格式问题
        const compressed = await compressImage(imageFile);
        const result = await uploadImage(compressed);
        imageUrl = result.url;
      } catch (e) {
        uploadError = e instanceof Error ? e.message : '图片上传失败';
      }
    }

    try {
      const recordId = await addLedgerRecord(
        activeTask,
        { note: note.trim() || undefined, imageUrl },
        { status: isParent ? 'approved' : 'pending' }
      );
      await loadLedger();
      closeTaskModal();
      notifySuccess(activeTask, recordId);
      if (uploadError) {
        message.warning({ content: `照片没传上去：${uploadError}（打卡本身已成功）`, duration: 6 });
      }
    } catch (e) {
      message.error(e instanceof Error ? e.message : '操作失败，请重试');
    } finally {
      setUploading(false);
    }
  };

  /** 打卡：写入流水（小孩端为待审批申请）并刷新余额 */
  const handleTask = async (task: TaskConfig) => {
    const blocked = checkTask(task);
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
        { status: isParent ? 'approved' : 'pending' }
      );
      await loadLedger();
      notifySuccess(task, recordId);
    } catch (e) {
      message.error(e instanceof Error ? e.message : '操作失败，请重试');
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
        { status: isParent ? 'approved' : 'pending' }
      );
      await loadLedger();
      form.resetFields();
      notifySuccess(task, recordId);
    } catch (e) {
      message.error(e instanceof Error ? e.message : '添加失败，请重试');
    }
  };

  if (error) {
    return <ErrorState description={error} onRetry={() => loadLedger().catch(() => undefined)} />;
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

  /** 审批通过 */
  const handleApprove = async (id: string) => {
    try {
      await approve(id);
      message.success('已审批通过，积分已入账');
    } catch (e) {
      message.error('操作失败，请重试');
    }
  };

  /** 审批驳回 */
  const handleReject = async (id: string) => {
    try {
      await reject(id);
      message.success('已驳回该申请');
    } catch (e) {
      message.error('操作失败，请重试');
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
        { status: 'approved' }
      );
      await loadLedger();
      message.success(`已兑现 ${amount} 积分，余额清零`);
    } catch (e) {
      message.error(e instanceof Error ? e.message : '结算失败，请重试');
    } finally {
      setSettling(false);
    }
  };

  /** 导出 CSV（仅家长）：按当前筛选导出全部记录，带 BOM 方便 Excel 直接打开中文 */
  const handleExportCsv = () => {
    const escapeCell = (value: string) => `"${value.replace(/"/g, '""')}"`;
    const header = ['时间', '任务', '类型', '积分', '状态', '备注', '图片'];
    const rows = filteredRecords.map((r) => [
      new Date(r.created_at).toLocaleString('zh-CN'),
      r.task_name,
      r.type === 'earning' ? '赚钱' : '消费/罚款',
      String(r.amount),
      r.status === 'pending' ? '待审批' : r.status === 'rejected' ? '已驳回' : '已入账',
      (r.note ?? '').replace(/[\r\n]+/g, ' '),
      r.image_url ?? '',
    ]);
    const csv = [header, ...rows].map((cells) => cells.map(escapeCell).join(',')).join('\r\n');
    const blob = new Blob([`\uFEFF${csv}`], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `sekainook-流水-${new Date().toISOString().slice(0, 10)}.csv`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
    message.success(`已导出 ${rows.length} 条记录`);
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
                disabled={isTaskDone(task)}
                onClick={() => openTaskModal(task)}
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
                disabled={isTaskDone(task)}
                onClick={() => openTaskModal(task)}
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
                  {/* 驳回后重新提交 */}
                  {record.status === 'rejected' && (
                    <Button size="small" className={styles.resubmitBtn} onClick={() => handleResubmit(record.id)}>
                      重新提交
                    </Button>
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
                    onClick={() => handleApprove(record.id)}
                  >
                    通过
                  </Button>
                  <Button size="small" icon={<CloseCircleOutlined />} onClick={() => handleReject(record.id)}>
                    驳回
                  </Button>
                </div>
              </div>
            </List.Item>
          )}
        />
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
          activeKey={activeTab}
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
              disabled={!homeworkTask || isTaskDone(homeworkTask)}
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
              disabled={!sleepTask || isTaskDone(sleepTask)}
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

      {/* ===== 任务打卡弹窗 ===== */}
      <Modal
        open={!!activeTask}
        title={activeTask ? `${isParent ? '打卡' : '申请打卡'}：${activeTask.name}` : ''}
        onCancel={closeTaskModal}
        onOk={handleTaskSubmit}
        okText={isParent ? '确认打卡' : '提交申请'}
        cancelText="取消"
        confirmLoading={uploading}
        // 手机端键盘弹出时不要把弹窗顶出屏幕：贴顶 + 内容区自己滚动
        style={{ top: 24 }}
        styles={{ body: { maxHeight: '60vh', overflowY: 'auto' } }}
        destroyOnHidden
      >
        {/* 上方：拍照 / 相册 双入口 */}
        <div className={styles.modalSection}>
          <div className={styles.modalLabel}>
            <CameraOutlined /> 上传照片
          </div>
          <div className={styles.uploadArea}>
            {imagePreview ? (
              <div className={styles.imagePreviewWrap}>
                <img src={imagePreview} alt="任务照片" className={styles.imagePreview} />
                <Button
                  size="small"
                  className={styles.imageRemove}
                  onClick={() => {
                    setImageFile(null);
                    setImagePreview(null);
                  }}
                >
                  移除
                </Button>
              </div>
            ) : (
              <div className={styles.uploadChoices}>
                {/* 拍照：capture 直接调起系统相机 */}
                <label className={styles.uploadBtn}>
                  <input
                    type="file"
                    accept="image/*"
                    capture="environment"
                    onChange={handleImageChange}
                    style={{ display: 'none' }}
                  />
                  <CameraOutlined />
                  <span>拍照</span>
                </label>
                {/* 相册：不带 capture，让系统弹「相机 / 相册 / 文件」选择 */}
                <label className={styles.uploadBtn}>
                  <input
                    type="file"
                    accept="image/*"
                    onChange={handleImageChange}
                    style={{ display: 'none' }}
                  />
                  <PictureOutlined />
                  <span>从相册选</span>
                </label>
              </div>
            )}
          </div>
        </div>

        {/* 下方：备注 */}
        <div className={styles.modalSection}>
          <div className={styles.modalLabel}>
            <PictureOutlined /> 备注
          </div>
          <Input.TextArea
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="填写任务备注（可选）"
            rows={3}
            maxLength={200}
            showCount
          />
        </div>
      </Modal>
    </div>
  );
}
