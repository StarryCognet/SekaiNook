import { useEffect, useRef } from 'react';

/**
 * 安卓硬件返回键兜底：active 为 true 时压入一条历史记录，
 * 用户按返回键触发 popstate → 关掉弹窗，而不是直接退出页面。
 *
 * 注意：弹窗被界面按钮（取消/确定）关掉时，要把刚才压入的那条历史弹回去，
 * 否则用户之后按一次返回会「什么也没发生」。
 *
 * ---------------------------------------------------------------------------
 * 多实例不变量（同一个页面同时挂多个实例时必须全部成立，否则会退化成
 * 「点一次取消退两层 / 按一次返回两层一起退」）：
 *
 *   ① 单栈：所有 active 实例按注册先后排进模块级 stack，**只有栈顶（最后注册者）
 *      才响应返回键** —— popstate 一律先查 event.state 上那条历史属于谁。
 *   ② 一号一历史：每个实例 active 期间刚好压入一条带自己唯一 id 的历史记录，
 *      id 单调递增，且与历史记录的先后顺序一致。
 *   ③ 认领靠比对：返回键落地后看落点那条历史的 id，**id 比落点大的那条就是刚被
 *      消费的记录**，只有它能拿到这次 onBack；落点就是栈顶自己时谁也拿不到。
 *   ④ 自己弹自己不算：cleanup 里发起的 history.back()（清理自己那条历史）用
 *      模块级 selfBacks 计数吞掉，绝不让这次 popstate 落到别的实例头上。
 *   ⑤ 消费过就不再弹：被返回键消费掉的实例在 cleanup 时不再 back()，避免用户
 *      之后要多按一次返回。
 *   ⑥ 无残留：window / history 只在 effect 里碰（SSR、测试环境不跑 effect 就不会炸）；
 *      popstate 监听只在第一次用到时挂一次并常驻（它要负责接收 ④ 那声回响，
 *      提前摘掉会让 selfBacks 计数漏下去，反而吞掉用户真正的一次返回）。
 * ---------------------------------------------------------------------------
 */

interface BackEntry {
  /** 唯一 id：写进历史记录 state，回来时靠它认领 */
  id: number;
  /** 是否已被返回键消费（消费掉的历史记录不用再 back()） */
  consumed: boolean;
  /** 关弹窗的回调（每次渲染刷新，读的是最新的那个） */
  handler: () => void;
}

/** 注册栈：按 id 升序，末位 = 栈顶 = 最后注册者 */
const stack: BackEntry[] = [];

/** 下一个可用 id */
let nextId = 1;

/** 自己发起的 history.back() 次数：这些 popstate 要被吞掉，不派发给任何实例 */
let selfBacks = 0;

/** popstate 监听是否已挂上（只挂一次，且不再摘） */
let listening = false;

/** 从历史记录 state 里取「这条属于哪个实例」；不是我们压的返回 -1 */
function readEntryId(state: unknown): number {
  if (state && typeof state === 'object') {
    const id = (state as { __sekainookModalId?: unknown }).__sekainookModalId;
    if (typeof id === 'number') return id;
  }
  return -1;
}

function handlePopState(event: PopStateEvent): void {
  // 自己发起的回退（cleanup 收拾自己那条历史）：只吞掉，不派发
  if (selfBacks > 0) {
    selfBacks -= 1;
    return;
  }

  // 没人注册时什么都不做（监听是常驻的，可能出现这种情况）
  const top = stack[stack.length - 1];
  if (!top) return;

  // 落点那条历史就是栈顶自己 → 没有任何实例的历史被消费掉
  if (top.id <= readEntryId(event.state)) return;

  top.consumed = true;
  stack.pop();
  top.handler();
}

function startListening(): void {
  if (listening || typeof window === 'undefined') return;
  window.addEventListener('popstate', handlePopState);
  listening = true;
}

export function useBackButton(active: boolean, onBack: () => void): void {
  const onBackRef = useRef(onBack);
  onBackRef.current = onBack;

  useEffect(() => {
    if (!active || typeof window === 'undefined') return;

    const entry: BackEntry = {
      id: nextId,
      consumed: false,
      handler: () => onBackRef.current(),
    };
    nextId += 1;

    stack.push(entry);
    startListening();
    window.history.pushState({ __sekainookModal: true, __sekainookModalId: entry.id }, '');

    return () => {
      const index = stack.indexOf(entry);
      if (index !== -1) stack.splice(index, 1);

      // 被返回键消费过的历史已经不在了，没什么要弹的
      if (entry.consumed) return;

      // 自己压的那条还在：替用户按一次回退。记一笔 selfBacks，
      // 免得这次 popstate 被还留在栈里的下层实例当成「用户按了返回」而误关。
      selfBacks += 1;
      window.history.back();
    };
  }, [active]);
}
