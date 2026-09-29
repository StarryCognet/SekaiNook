import { useEffect, useState } from 'react';
import { WarningOutlined } from '@ant-design/icons';
import styles from './RefreshFailedBar.module.css';

interface RefreshFailedBarProps {
  /** 点「重试」时调用；返回 Promise 时按钮会显示「重试中…」 */
  onRetry: () => void | Promise<void>;
  /** 自定义文案（默认针对网络问题） */
  text?: string;
}

/**
 * 拉取失败时的显式提示条。
 *
 * 以前首页的加载用的是 `.catch(() => undefined)`：请求失败时页面照样渲染，
 * 只是「余额」显示 0、「待审批」显示 0 —— 妈妈会以为孩子这周没赚到分，
 * 而不是「没拉到」。所以失败必须看得见，并且能就地重试。
 */
export default function RefreshFailedBar({ onRetry, text }: RefreshFailedBarProps) {
  const [retrying, setRetrying] = useState(false);
  // 重新联网后这种条不该老挂着：每次挂载都当做一次新的失败提示
  const [mountedAt, setMountedAt] = useState(0);

  useEffect(() => {
    setMountedAt(Date.now());
  }, []);

  const handleRetry = async () => {
    setRetrying(true);
    try {
      await onRetry();
    } finally {
      setRetrying(false);
    }
  };

  return (
    <button
      type="button"
      className={styles.bar}
      onClick={handleRetry}
      disabled={retrying}
      data-since={mountedAt}
    >
      <WarningOutlined className={styles.icon} />
      <span className={styles.text}>{text ?? '网络不太好，最新数据没拉到'}</span>
      <span className={styles.action}>{retrying ? '重试中…' : '点这里重试'}</span>
    </button>
  );
}
