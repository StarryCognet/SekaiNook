import { useEffect, useState } from 'react';
import { Button, Card, List, Tag, Tabs, Form, Input, Select, InputNumber, Modal, Image, message, Badge } from 'antd';
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
} from '@ant-design/icons';
import { addLedgerRecord, resubmitRequest } from '../../api/familyLedger';
import { uploadImage } from '../../api/upload';
import { getTasksByType } from '../../config/familyRules';
import { useFamilyStore } from '../../store/useFamilyStore';
import { PageLoading, EmptyState, ErrorState } from '../../components/StateViews';
import { designTokens } from '../../theme/tokens';
import type { LedgerRecord, TaskConfig, TaskType } from '../../types/family';
import styles from './FamilyDashboard.module.css';

/** 自定义任务表单值 */
interface CustomTaskForm {
  type: TaskType;
  name: string;
  value: number;
}

/** 核心仪表盘：积分银行 + 任务区 / 待审批区 / 历史记录区 */
export default function FamilyDashboard() {
  const { balance, records, pendingRecords, pendingCount, loading, role, loadLedger, refreshPending, approve, reject } = useFamilyStore();
  const [error, setError] = useState<string | null>(null);
  const [now, setNow] = useState(new Date());
  const [activeTab, setActiveTab] = useState('tasks');
  const [form] = Form.useForm<CustomTaskForm>();

  const isParent = role === 'parent';

  // 任务打卡弹窗状态
  const [activeTask, setActiveTask] = useState<TaskConfig | null>(null);
  const [note, setNote] = useState('');
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);

  const earningTasks = getTasksByType('earning');
  const spendingTasks = getTasksByType('spending');

  // 初始化加载
  useEffect(() => {
    loadLedger().catch((e) => setError(e instanceof Error ? e.message : '加载失败'));
  }, [loadLedger]);

  // 每秒刷新当前时间（用于作息判断）
  useEffect(() => {
    const timer = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(timer);
  }, []);

  // 家长端：轮询待审批数量（角标实时性），10s 间隔 + 页面重新可见时立即刷新
  useEffect(() => {
    if (!isParent) return;
    const refresh = () => refreshPending().catch(() => undefined);
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

  // 小孩端：放宽到 15s 轮询流水，感知审批结果
  useEffect(() => {
    if (isParent) return;
    const timer = setInterval(() => loadLedger().catch(() => undefined), 15000);
    return () => clearInterval(timer);
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

  /** 选择图片（相机或相册） */
  const handleImageChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setImageFile(file);
    setImagePreview(URL.createObjectURL(file));
    e.target.value = '';
  };

  /** 提交任务打卡：上传图片（如有）→ 写入流水 */
  const handleTaskSubmit = async () => {
    if (!activeTask) return;
    let imageUrl: string | undefined;
    let uploadFailed = false;

    // 上传图片（失败不阻断打卡，仅提示）
    if (imageFile) {
      setUploading(true);
      try {
        const result = await uploadImage(imageFile);
        if (result) imageUrl = result.url;
      } catch (e) {
        uploadFailed = true;
      }
    }

    try {
      await addLedgerRecord(
        activeTask,
        { note: note.trim() || undefined, imageUrl },
        { status: isParent ? 'approved' : 'pending' }
      );
      await loadLedger();
      if (isParent) {
        const sign = activeTask.value > 0 ? '+' : '';
        message.success(`${sign}${activeTask.value} 积分！${activeTask.name}${activeTask.value > 0 ? '真棒' : ''}`);
      } else {
        message.success(`已提交打卡「${activeTask.name}」，等待家长审批`);
      }
      if (uploadFailed) {
        message.warning(isParent ? '图片上传失败，但打卡已成功' : '图片上传失败，但申请已提交');
      }
      closeTaskModal();
    } catch (e) {
      message.error('操作失败，请重试');
    } finally {
      setUploading(false);
    }
  };

  /** 打卡：写入流水（小孩端为待审批申请）并刷新余额 */
  const handleTask = async (task: TaskConfig) => {
    try {
      await addLedgerRecord(task, undefined, { status: isParent ? 'approved' : 'pending' });
      await loadLedger();
      if (isParent) {
        const sign = task.value > 0 ? '+' : '';
        message.success(`${sign}${task.value} 积分！${task.name}${task.value > 0 ? '真棒' : ''}`);
      } else {
        message.success(`已提交打卡「${task.name}」，等待家长审批`);
      }
    } catch (e) {
      message.error('操作失败，请重试');
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
      await addLedgerRecord(task, undefined, { status: isParent ? 'approved' : 'pending' });
      await loadLedger();
      form.resetFields();
      if (isParent) {
        message.success(`已添加自定义任务「${task.name}」`);
      } else {
        message.success(`已提交「${task.name}」，等待家长审批`);
      }
    } catch (e) {
      message.error('添加失败，请重试');
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
      {records.length === 0 ? (
        <EmptyState description="暂无流水记录" />
      ) : (
        <List
          dataSource={records}
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
                {/* 驳回后重新提交 */}
                {record.status === 'rejected' && (
                  <Button size="small" className={styles.resubmitBtn} onClick={() => handleResubmit(record.id)}>
                    重新提交
                  </Button>
                )}
              </div>
            </List.Item>
          )}
        />
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

      {/* ===== 右侧：今日任务与作息 ===== */}
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
              onClick={() =>
                handleTask(getTasksByType('earning').find((t) => t.id === 'finish_homework')!)
              }
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
              onClick={() =>
                handleTask(getTasksByType('earning').find((t) => t.id === 'sleep_on_time')!)
              }
            >
              按时睡觉
            </Button>
          </div>
        </Card>
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
        destroyOnClose
      >
        {/* 上方：拍照上传 */}
        <div className={styles.modalSection}>
          <div className={styles.modalLabel}>
            <CameraOutlined /> 拍照上传
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
              <label className={styles.uploadBtn}>
                <input
                  type="file"
                  accept="image/*"
                  capture="environment"
                  onChange={handleImageChange}
                  style={{ display: 'none' }}
                />
                <CameraOutlined />
                <span>点击拍照</span>
              </label>
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
