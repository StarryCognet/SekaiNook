import { Component, type ErrorInfo, type ReactNode } from 'react';

/**
 * 懒加载 chunk 拉取失败的典型错误文本。
 * 发布后旧构建的 assets/<hash>.js 已被清掉，页面里还留着旧引用时就会命中这些。
 */
const CHUNK_ERROR_HINTS: readonly string[] = [
  'Failed to fetch dynamically imported module',
  'Importing a module script failed',
  'error loading dynamically imported module',
  'Unable to preload CSS',
  'Loading chunk',
  'ChunkLoadError',
];

/** 模块级标记：整个页面会话里只自动刷新一次，避免「失败 → 刷新 → 又失败」的死循环 */
let autoReloadedForChunk = false;

interface ErrorBoundaryProps {
  children: ReactNode;
}

interface ErrorBoundaryState {
  error: Error | null;
}

/**
 * 全局错误边界：渲染期异常不再白屏，改为一张中文卡片 +「重新加载」按钮。
 *
 * 这里刻意只用原生 DOM + 内联样式，不依赖 antd 也不依赖 CSS Modules：
 * 出错时组件/样式 chunk 本身可能就没加载成功，再用它们有二次抛错的风险
 * （边界自身的 fallback 再抛错就真的白屏了）。
 *
 * 旧 chunk 404（懒加载 import 失败）时先自动刷新一次去拿新构建；
 * 刷新后仍失败就停在卡片上交给用户，不会无限刷新。
 */
export default class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  state: ErrorBoundaryState = { error: null };

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    // 留一条控制台线索，真机排查时能看到组件栈
    console.error('[ErrorBoundary]', error, info.componentStack);

    if (autoReloadedForChunk) return;
    const text = `${error.name} ${error.message}`;
    if (CHUNK_ERROR_HINTS.some((hint) => text.includes(hint))) {
      autoReloadedForChunk = true;
      window.location.reload();
    }
  }

  /** 手动重新加载：用户点的，不受自动刷新标记限制 */
  private handleReload = (): void => {
    window.location.reload();
  };

  render(): ReactNode {
    const { error } = this.state;
    if (!error) return this.props.children;

    return (
      <div
        style={{
          minHeight: '100vh',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: 24,
          background: '#f5f5f5',
          color: '#262626',
          fontFamily:
            '-apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif',
        }}
      >
        <div
          style={{
            width: '100%',
            maxWidth: 360,
            padding: '28px 24px',
            borderRadius: 16,
            background: '#ffffff',
            boxShadow: '0 6px 24px rgba(0, 0, 0, 0.08)',
            textAlign: 'center',
          }}
        >
          <div style={{ fontSize: 40, lineHeight: 1, marginBottom: 12 }} aria-hidden="true">
            🌱
          </div>
          <h1 style={{ fontSize: 20, margin: '0 0 8px' }}>页面出了点问题</h1>
          <p style={{ margin: '0 0 20px', fontSize: 14, lineHeight: 1.6, color: '#595959' }}>
            刚才加载出错了，重新加载一下通常就好了。
          </p>
          <button
            type="button"
            onClick={this.handleReload}
            style={{
              width: '100%',
              padding: '10px 16px',
              fontSize: 15,
              color: '#ffffff',
              background: '#1677ff',
              border: 'none',
              borderRadius: 8,
              cursor: 'pointer',
            }}
          >
            重新加载
          </button>
          <p
            style={{
              margin: '16px 0 0',
              fontSize: 12,
              lineHeight: 1.5,
              color: '#8c8c8c',
              wordBreak: 'break-all',
            }}
          >
            {error.message}
          </p>
        </div>
      </div>
    );
  }
}
