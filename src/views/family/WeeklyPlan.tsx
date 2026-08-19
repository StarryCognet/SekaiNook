import { useEffect, useMemo, useState } from 'react';
import { Button, Card, InputNumber, Progress, Tag, message } from 'antd';
import {
  PlusOutlined,
  BookOutlined,
  ReadOutlined,
  CalculatorOutlined,
  HomeOutlined,
  CheckCircleFilled,
} from '@ant-design/icons';
import { fetchWeeklyPlans, updateWeeklyPlan } from '../../api/familyTasks';
import { ensureLocalWeeklyPlans } from '../../api/supabaseClient';
import { WEEKLY_PLAN_TEMPLATE } from '../../config/familyRules';
import { getCurrentWeekLabel } from '../../utils/week';
import { PageLoading, EmptyState, ErrorState } from '../../components/StateViews';
import { designTokens } from '../../theme/tokens';
import type { WeeklyPlan } from '../../types/family';
import styles from './WeeklyPlan.module.css';

/** 科目图标映射 */
const SUBJECT_ICONS: Record<string, React.ReactNode> = {
  英语: <BookOutlined />,
  语文: <ReadOutlined />,
  数学: <CalculatorOutlined />,
  日常: <HomeOutlined />,
};

/** 每周学习计划表 */
export default function WeeklyPlan() {
  const weekLabel = getCurrentWeekLabel();
  const [plans, setPlans] = useState<WeeklyPlan[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [inputs, setInputs] = useState<Record<string, number>>({});

  useEffect(() => {
    // 本地数据库模式下，先初始化本周计划数据
    (async () => {
      try {
        await ensureLocalWeeklyPlans();
        const data = await fetchWeeklyPlans(weekLabel);
        setPlans(data);
        const init: Record<string, number> = {};
        data.forEach((p) => {
          init[p.id] = p.current;
        });
        setInputs(init);
      } catch (e) {
        setError(e instanceof Error ? e.message : '加载失败');
      } finally {
        setLoading(false);
      }
    })();
  }, [weekLabel]);

  // 按科目分组（以模板顺序为准）
  const grouped = useMemo(() => {
    const map = new Map<string, typeof WEEKLY_PLAN_TEMPLATE>();
    WEEKLY_PLAN_TEMPLATE.forEach((tpl) => {
      if (!map.has(tpl.subject)) map.set(tpl.subject, []);
      map.get(tpl.subject)!.push(tpl);
    });
    return Array.from(map.entries());
  }, []);

  // 数据库中的计划按 task_name 索引
  const planByTask = useMemo(() => {
    const map = new Map<string, WeeklyPlan>();
    plans.forEach((p) => map.set(p.task_name, p));
    return map;
  }, [plans]);

  // 总体进度
  const totalTarget = plans.reduce((s, p) => s + p.target, 0);
  const totalCurrent = plans.reduce((s, p) => s + p.current, 0);
  const overallPercent = totalTarget > 0 ? Math.round((totalCurrent / totalTarget) * 100) : 0;

  const handleAdd = async (plan: WeeklyPlan) => {
    const next = (inputs[plan.id] ?? plan.current) + 1;
    try {
      await updateWeeklyPlan(plan.id, next);
      setInputs((prev) => ({ ...prev, [plan.id]: next }));
      setPlans((prev) => prev.map((p) => (p.id === plan.id ? { ...p, current: next } : p)));
      message.success('进度已更新');
    } catch (e) {
      message.error('更新失败');
    }
  };

  if (error) {
    return <ErrorState description={error} onRetry={() => window.location.reload()} />;
  }

  if (loading) {
    return <PageLoading />;
  }

  if (plans.length === 0) {
    return (
      <div className={styles.wrap}>
        <div className={styles.header}>
          <span className={`num ${styles.weekLabel}`}>{weekLabel}</span>
          <span className={styles.headerTitle}>本周学习计划</span>
        </div>
        <EmptyState description="本周暂无学习计划，请先在 Supabase 中初始化数据" />
      </div>
    );
  }

  return (
    <div className={styles.wrap}>
      {/* 顶部：周标签 + 总体进度 */}
      <Card className={styles.headerCard}>
        <div className={styles.header}>
          <span className={`num ${styles.weekLabel}`}>{weekLabel}</span>
          <span className={styles.headerTitle}>本周学习计划</span>
        </div>
        <div className={styles.overall}>
          <span className={styles.overallLabel}>总体完成度</span>
          <Progress
            percent={overallPercent}
            strokeColor={designTokens.colors.success}
            className={styles.overallBar}
          />
        </div>
      </Card>

      {/* 按科目分组 */}
      {grouped.map(([subject, tasks]) => (
        <Card
          key={subject}
          className={styles.subjectCard}
          title={
            <span className={styles.subjectTitle}>
              <span className={styles.subjectIcon}>{SUBJECT_ICONS[subject]}</span>
              {subject}
            </span>
          }
          variant="borderless"
        >
          {tasks.map((tpl) => {
            const plan = planByTask.get(tpl.task_name);
            const done = plan ? plan.current >= plan.target : false;
            const current = plan ? plan.current : 0;
            const percent = plan ? Math.min(100, Math.round((current / plan.target) * 100)) : 0;

            return (
              <div
                key={tpl.task_name}
                className={`${styles.row} ${done ? styles.rowDone : ''}`}
              >
                <div className={styles.rowInfo}>
                  <div className={styles.rowName}>
                    {tpl.task_name}
                    {done && <CheckCircleFilled className={styles.doneIcon} />}
                  </div>
                  <div className={styles.rowMeta}>
                    <span className="num">{current}</span> / <span className="num">{tpl.target}</span>
                  </div>
                </div>
                <Progress
                  percent={percent}
                  size="small"
                  strokeColor={done ? designTokens.colors.success : designTokens.colors.primary}
                  className={styles.rowBar}
                />
                {plan ? (
                  <div className={styles.rowActions}>
                    {done && <Tag color="success">已完成</Tag>}
                    <InputNumber
                      min={0}
                      value={inputs[plan.id] ?? plan.current}
                      onChange={(v) => setInputs((prev) => ({ ...prev, [plan.id]: v ?? 0 }))}
                      size="small"
                      style={{ width: 72 }}
                    />
                    <Button
                      type="primary"
                      size="small"
                      icon={<PlusOutlined />}
                      className="btn-press"
                      style={{
                        background: done ? designTokens.colors.success : designTokens.colors.primary,
                        borderColor: done ? designTokens.colors.success : designTokens.colors.primary,
                      }}
                      onClick={() => handleAdd(plan)}
                    >
                      增加
                    </Button>
                  </div>
                ) : (
                  <span className={styles.noData}>未初始化</span>
                )}
              </div>
            );
          })}
        </Card>
      ))}
    </div>
  );
}