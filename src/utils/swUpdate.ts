/**
 * Service Worker 注册与「有新版本」提示。
 *
 * 版本链路：vite.config.ts 注入 __BUILD_ID__ → 这里用 /sw.js?v=<id> 注册
 * → sw.js 从 URL 取 id 当缓存名 → 新构建必然产生新脚本 URL 与新缓存名
 * → activate 清掉旧缓存并 claim 页面 → 本模块监听到接管后提示用户刷新。
 *
 * 提示刻意用 window.confirm，不碰 antd 的 notification：
 * 这个时机 React 可能还没挂载（或已白屏），静态方法拿不到 AntApp 上下文。
 */

/** 已触发过刷新：updatefound 与 controllerchange 可能都命中，只允许刷新一次防死循环 */
let reloading = false;

/** 问一次用户是否立刻刷新；确认后只刷新一次 */
function askReload(message: string): void {
  if (reloading) return;
  if (!window.confirm(message)) return;
  reloading = true;
  window.location.reload();
}

/** 注册 Service Worker，并监听两种「新版本已就绪」的信号 */
export function registerServiceWorker(): void {
  if (!('serviceWorker' in navigator)) return;

  // 进页面时是否已被某个 SW 控制：false = 这是首次安装，不需要提示刷新
  const hadController = Boolean(navigator.serviceWorker.controller);

  // 新 SW 执行 skipWaiting + clients.claim 后会立刻接管本页，此时旧资源该换了
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (hadController) askReload('有新版本，点确定立即刷新');
  });

  window.addEventListener('load', () => {
    void (async () => {
      try {
        const registration = await navigator.serviceWorker.register(`/sw.js?v=${__BUILD_ID__}`);

        registration.addEventListener('updatefound', () => {
          const installing = registration.installing;
          if (!installing) return;

          installing.addEventListener('statechange', () => {
            // installed 且本页已被 SW 控制 = 这是一次更新（而不是首次安装）
            if (installing.state === 'installed' && navigator.serviceWorker.controller) {
              askReload('有新版本，点确定立即刷新');
            }
          });
        });
      } catch {
        // 注册失败（隐私模式 / 浏览器不支持）不影响正常使用
      }
    })();
  });
}
