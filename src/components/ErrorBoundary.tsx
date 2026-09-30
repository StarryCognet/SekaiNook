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

/** 命中下面的错误文本就当作「chunk 没拉到」 */
function isChunkError(error: Error): boolean {
  const text = `${error.name} ${error.message}`;
  return CHUNK_ERROR_HINTS.some((hint) => text.includes(hint));
}

/** 「已经自动刷新过一次」的持久化键：见 autoReloadedForChunk 的说明 */
const AUTO_RELOAD_KEY = 'sekainook_chunk_autoreload';

function readAutoReloaded(): boolean {
  try {
    return sessionStorage.getItem(AUTO_RELOAD_KEY) === '1';
  } catch {
    // 隐私模式下 sessionStorage 可能直接抛错：当成没刷新过
    return false;
  }
}

/**
 * 模块级标记：整个页面会话里只自动刷新一次，避免「失败 → 刷新 → 又失败」的死循环。
 * 同时往 sessionStorage 记一份：模块级变量会随刷新重置，只靠它会退化成「每次
 * 刷新都算第一次」，于是二次失败继续自动刷新、用户永远看不到按钮。写上 sessionStorage
 * 之后，同一次会话里的第二次失败就停在卡片上，等用户点「重新加载」。
 */
let autoReloadedForChunk = readAutoReloaded();

/** 记下「这次会话已经自动刷新过」 */
function markAutoReloaded(): void {
  autoReloadedForChunk = true;
  try {
    sessionStorage.setItem(AUTO_RELOAD_KEY, '1');
  } catch {
    /* 存不住也不影响本次会话内的标记 */
  }
}

type ErrorBoundaryVariant = 'page' | 'section';

interface ErrorBoundaryProps {
  children: ReactNode;
  /**
   * page：整页兜底，占满屏幕（应用最外层）；
   * section：内容区二级兜底，不占满屏，顶栏/底栏还在，边界内换成一张小卡片。
   */
  variant?: ErrorBoundaryVariant;
  /**
   * 变了就自动清掉错误：二级边界挂在 MainLayout 里跨路由不卸载，
   * 切页时把 resetKey 传成 location.pathname，用户不用卡在错误页上。
   */
  resetKey?: string;
}

interface ErrorBoundaryState {
  error: Error | null;
}

/**
 * 错误边界：渲染期异常不再白屏，改为一张中文卡片 +「重新加载」按钮。
 *
 * 这里刻意只用原生 DOM + 内联样式，不依赖 antd 也不依赖 CSS Modules：
 * 出错时组件/样式 chunk 本身可能就没加载成功，再用它们有二次抛错的风险
 * （边界自身的 fallback 再抛错就真的白屏了）。
 * 颜色走主题 CSS 变量（见 theme/global.css）并带上浅色兜底值：深色主题下不再是白屏。
 *
 * 旧 chunk 404（懒加载 import 失败）时先自动刷新一次去拿新构建；
 * 刷新后仍失败就停在卡片上交给用户点按钮，不会无限刷新。
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
    if (isChunkError(error)) {
      markAutoReloaded();
      window.location.reload();
    }
  }

  /** 路由（resetKey）变了：清掉错误，让新页面正常渲染（旧页面的树会整棵重建） */
  componentDidUpdate(prevProps: ErrorBoundaryProps): void {
    if (this.state.error && prevProps.resetKey !== this.props.resetKey) {
      this.setState({ error: null });
    }
  }

  /** 手动重新加载：用户点的，不受自动刷新标记限制 */
  private handleReload = (): void => {
    window.location.reload();
  };

  /** 原地重试：只清错误状态，重新渲染子树（懒加载失败时多半要等网络回暖） */
  private handleRetry = (): void => {
    this.setState({ error: null });
  };

  render(): ReactNode {
    const { error } = this.state;
    if (!error) return this.props.children;

    const section = this.props.variant === 'section';
    const chunkFailed = isChunkError(error);

    return (
      <div
        style={{
          // 二级边界不占满屏：只把内容区换成卡片，顶栏 / 底栏照常可用
          minHeight: section ? 0 : '100vh',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: 24,
          background: section ? 'transparent' : 'var(--color-bg, #f5f6fa)',
          color: 'var(--color-text, #262626)',
          fontFamily:
            '-apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif',
        }}
      >
        <div
          style={{
            width: '100%',
            maxWidth: 360,
            padding: section ? '20px 20px' : '28px 24px',
            borderRadius: 16,
            background: 'var(--color-surface, #ffffff)',
            boxShadow: '0 6px 24px rgba(0, 0, 0, 0.08)',
            textAlign: 'center',
          }}
        >
          <div style={{ fontSize: section ? 32 : 40, lineHeight: 1, marginBottom: 12 }} aria-hidden="true">
            🌱
          </div>
          <h1 style={{ fontSize: 20, margin: '0 0 8px' }}>页面出了点问题</h1>
          <p
            style={{
              margin: '0 0 20px',
              fontSize: 14,
              lineHeight: 1.6,
              color: 'var(--color-text-secondary, #595959)',
            }}
          >
            {chunkFailed && autoReloadedForChunk
              ? '新版本可能刚发布，自动刷新过一次还是没成功，点下面的按钮再加载一次。'
              : section
                ? '这一块没加载出来，重新加载一下；也可以先切到别的页面继续用。'
                : '刚才加载出错了，重新加载一下通常就好了。'}
          </p>
          <button
            type="button"
            onClick={this.handleReload}
            style={{
              width: '100%',
              padding: '10px 16px',
              fontSize: 15,
              color: '#ffffff',
              background: 'var(--color-primary, #1677ff)',
              border: 'none',
              borderRadius: 8,
              cursor: 'pointer',
            }}
          >
            重新加载
          </button>
          {section && (
            <button
              type="button"
              onClick={this.handleRetry}
              style={{
                width: '100%',
                marginTop: 10,
                padding: '10px 16px',
                fontSize: 15,
                color: 'var(--color-text, #262626)',
                background: 'transparent',
                border: '1px solid var(--color-border, #d9d9d9)',
                borderRadius: 8,
                cursor: 'pointer',
              }}
            >
              重试
            </button>
          )}
          <p
            style={{
              margin: '16px 0 0',
              fontSize: 12,
              lineHeight: 1.5,
              color: 'var(--color-text-tertiary, #8c8c8c)',
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
