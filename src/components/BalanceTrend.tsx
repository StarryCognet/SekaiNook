import { useEffect, useMemo, useRef } from 'react';
import { Card } from 'antd';
import { LineChartOutlined } from '@ant-design/icons';
import * as echarts from 'echarts/core';
import { BarChart } from 'echarts/charts';
import { GridComponent, TooltipComponent } from 'echarts/components';
import { CanvasRenderer } from 'echarts/renderers';
import type { EChartsOption } from 'echarts';
import { designTokens } from '../theme/tokens';
import type { LedgerRecord } from '../types/family';
import styles from './BalanceTrend.module.css';

// 按需注册：只打包柱状图 + 直角坐标系 + 提示框 + Canvas 渲染器。
// 直接 import 'echarts' 会把整个 echarts（约 1MB）塞进首屏，这里必须走 echarts/core。
// 同时不引入 echarts-for-react —— 它的 tslib 依赖在本项目未安装，会把未解析的
// `import ... from "tslib"` 打进产物，导致整块 chunk 在浏览器里加载失败。
echarts.use([BarChart, GridComponent, TooltipComponent, CanvasRenderer]);

/** 趋势图展示天数 */
const TREND_DAYS = 14;
/** 图表高度（px） */
const CHART_HEIGHT = 160;

interface BalanceTrendProps {
  /** 用于统计的流水（调用方已按成员筛选） */
  records: LedgerRecord[];
}

/** 按天汇总「已入账」积分，返回近 TREND_DAYS 天的日期标签与每日净值 */
function buildTrend(records: LedgerRecord[]): { labels: string[]; values: number[] } {
  const labels: string[] = [];
  const values: number[] = [];
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  for (let offset = TREND_DAYS - 1; offset >= 0; offset -= 1) {
    const day = new Date(today);
    day.setDate(day.getDate() - offset);
    const key = day.toDateString();
    labels.push(`${day.getMonth() + 1}/${day.getDate()}`);
    values.push(
      records
        .filter(
          (r) =>
            (!r.status || r.status === 'approved') &&
            new Date(r.created_at).toDateString() === key
        )
        .reduce((sum, r) => sum + r.amount, 0)
    );
  }

  return { labels, values };
}

/** 极简 echarts 容器：负责初始化、随容器尺寸自适应、卸载时销毁 */
function ChartCanvas({ option }: { option: EChartsOption }) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const chartRef = useRef<ReturnType<typeof echarts.init> | null>(null);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return undefined;

    const chart = echarts.init(el);
    chartRef.current = chart;

    // 侧边栏收起/窗口旋转都会改变容器宽度，交给 ResizeObserver 重新测量
    const observer =
      typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(() => chart.resize());
    observer?.observe(el);

    return () => {
      observer?.disconnect();
      chart.dispose();
      chartRef.current = null;
    };
  }, []);

  useEffect(() => {
    // notMerge = true：筛选/成员切换后完全按新数据重画，不留上一次的残留系列
    chartRef.current?.setOption(option, true);
  }, [option]);

  return <div ref={containerRef} style={{ width: '100%', height: CHART_HEIGHT }} />;
}

/** 近 14 天积分趋势（正收益绿柱、支出罚款红柱） */
export default function BalanceTrend({ records }: BalanceTrendProps) {
  const { labels, values } = useMemo(() => buildTrend(records), [records]);
  const hasData = values.some((value) => value !== 0);

  const option = useMemo<EChartsOption>(
    () => ({
      grid: { left: 0, right: 4, top: 12, bottom: 0, containLabel: true },
      tooltip: { trigger: 'axis', valueFormatter: (value) => `${value} 积分` },
      xAxis: {
        type: 'category',
        data: labels,
        axisLine: { lineStyle: { color: designTokens.colors.border } },
        axisTick: { show: false },
        axisLabel: {
          color: designTokens.colors.textSecondary,
          fontSize: designTokens.font.sizeXs,
          interval: 1,
        },
      },
      yAxis: {
        type: 'value',
        splitLine: { lineStyle: { color: designTokens.colors.border } },
        axisLabel: {
          color: designTokens.colors.textSecondary,
          fontSize: designTokens.font.sizeXs,
        },
      },
      series: [
        {
          type: 'bar',
          barMaxWidth: 18,
          data: values.map((value) => ({
            value,
            itemStyle: {
              color: value >= 0 ? designTokens.colors.success : designTokens.colors.danger,
              borderRadius: value >= 0 ? [3, 3, 0, 0] : [0, 0, 3, 3],
            },
          })),
        },
      ],
    }),
    [labels, values]
  );

  return (
    <Card className={styles.trendCard} variant="borderless">
      <div className={styles.trendTitle}>
        <LineChartOutlined /> 近 {TREND_DAYS} 天积分趋势
      </div>
      {hasData ? (
        <ChartCanvas option={option} />
      ) : (
        <div className={styles.trendEmpty}>最近 {TREND_DAYS} 天还没有积分记录</div>
      )}
    </Card>
  );
}
