import { useCallback, useState } from 'react';

/**
 * 跨页面切换保留的界面状态（Tab 选中项、筛选条件、已加载条数……）。
 *
 * 场景：从「家庭」切到「花园」再切回来，页面组件会被重新挂载，
 * 普通的 useState 会把这些选择全部重置 —— 而 iOS 的 tab 语义是每个 Tab
 * 保留自己的栈，回来时应该还是刚才的样子。
 *
 * 用法与 useState 完全一致（setter 同样支持函数式更新）：
 *   const [activeTab, setActiveTab] = useViewState('family.activeTab', 'tasks');
 *
 * 只放「选择类」的小状态：不要放弹窗开关、临时草稿这类一次性的东西。
 */

const PREFIX = 'sekainook_view_v1_';
/** 进程内缓存：同一次会话里连 sessionStorage 都不用读 */
const cache = new Map<string, unknown>();

function read<T>(key: string): T | undefined {
  if (cache.has(key)) return cache.get(key) as T;
  try {
    const raw = sessionStorage.getItem(PREFIX + key);
    if (raw === null) return undefined;
    const parsed = JSON.parse(raw) as T;
    cache.set(key, parsed);
    return parsed;
  } catch {
    return undefined;
  }
}

function write(key: string, value: unknown): void {
  cache.set(key, value);
  try {
    sessionStorage.setItem(PREFIX + key, JSON.stringify(value));
  } catch {
    /* 隐私模式下可能抛错，只留内存缓存即可 */
  }
}

/** 与 useState 同签名，但同一 key 的状态在页面卸载后依然保留 */
export function useViewState<T>(
  key: string,
  initial: T
): [T, (value: T | ((prev: T) => T)) => void] {
  const [value, setValue] = useState<T>(() => read<T>(key) ?? initial);

  const set = useCallback(
    (next: T | ((prev: T) => T)) => {
      setValue((prev) => {
        const resolved = typeof next === 'function' ? (next as (p: T) => T)(prev) : next;
        write(key, resolved);
        return resolved;
      });
    },
    [key]
  );

  return [value, set];
}

/**
 * 直接写某个界面状态（不经过组件）。
 * 用于「跳过去并顺手切到某个 Tab」这类跨页动作，例如首页的「去审批」按钮：
 * 先把 family.activeTab 写成 pending，再跳到 /family，账本页挂载时就落在待审批页。
 */
export function setViewState<T>(key: string, value: T): void {
  write(key, value);
}
