import { Empty, Result, Spin } from 'antd';
import { designTokens } from '../theme/tokens';

/** 全局加载态 */
export function PageLoading() {
  return (
    <div
      style={{
        display: 'flex',
        justifyContent: 'center',
        alignItems: 'center',
        minHeight: 320,
      }}
    >
      <Spin size="large" />
    </div>
  );
}

/** 全局空态 */
export function EmptyState({ description = '暂无数据' }: { description?: string }) {
  return <Empty description={description} style={{ padding: designTokens.spacing.xl }} />;
}

/** 全局错误态 */
export function ErrorState({
  description = '加载失败，请稍后重试',
  onRetry,
}: {
  description?: string;
  onRetry?: () => void;
}) {
  return (
    <Result
      status="error"
      title="出错了"
      subTitle={description}
      extra={
        onRetry ? (
          <button onClick={onRetry} style={{ color: designTokens.colors.primary }}>
            重试
          </button>
        ) : undefined
      }
    />
  );
}