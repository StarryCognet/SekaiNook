import { useEffect, useRef } from 'react';

/**
 * 安卓硬件返回键兜底：active 为 true 时压入一条历史记录，
 * 用户按返回键触发 popstate → 关掉弹窗，而不是直接退出页面。
 *
 * 注意：弹窗被界面按钮（取消/确定）关掉时，要把刚才压入的那条历史弹回去，
 * 否则用户之后按一次返回会「什么也没发生」。
 */
export function useBackButton(active: boolean, onBack: () => void) {
  const onBackRef = useRef(onBack);
  onBackRef.current = onBack;
  const pushedRef = useRef(false);

  useEffect(() => {
    if (!active) return;

    window.history.pushState({ __sekainookModal: true }, '');
    pushedRef.current = true;

    const handlePop = () => {
      // 返回键已被按下：我们自己压的那条历史已经出栈，交给 React 关弹窗即可
      pushedRef.current = false;
      onBackRef.current();
    };

    window.addEventListener('popstate', handlePop);
    return () => {
      window.removeEventListener('popstate', handlePop);
      if (pushedRef.current) {
        pushedRef.current = false;
        window.history.back();
      }
    };
  }, [active]);
}
