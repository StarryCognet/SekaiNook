/** 判断当前是否为移动端设备（宽度 < 768px） */
export function isMobile(): boolean {
  if (typeof window === 'undefined') return false;
  return window.innerWidth < 768;
}

/** 监听窗口尺寸变化，返回是否移动端（用于响应式布局） */
export function subscribeIsMobile(callback: (mobile: boolean) => void): () => void {
  const handle = () => callback(isMobile());
  window.addEventListener('resize', handle);
  return () => window.removeEventListener('resize', handle);
}