/**
 * Service Worker 注册与「有新版本」提示。
 *
 * 版本链路：vite.config.ts 注入 __BUILD_ID__ → 这里用 /sw.js?v=<id> 注册
 * → sw.js 从 URL 取 id 当缓存名 → 新构建必然产生新脚本 URL 与新缓存名。
 *
 * 接管时机刻意由用户决定（配合 public/sw.js）：
 *   - 新 SW 装好后停在 waiting，**不会**自动 skipWaiting；
 *   - 只有用户点了「确定」才 postMessage({ type: 'SKIP_WAITING' })，
 *     新 SW 接管本页（controllerchange）后才刷新一次。
 * 这样后台一发布，旧页面不会被新 SW 立刻接管：旧构建里尚未加载过的懒加载
 * chunk 仍然取得到（上一代缓存也留了一代兜底），页面内状态不会白丢。
 *
 * 提示刻意用 window.confirm，不碰 antd 的 notification：
 * 这个时机 React 可能还没挂载（或已白屏），静态方法拿不到 AntApp 上下文。
 */

/** 已触发过刷新：controllerchange 可能多次命中，只允许刷新一次防死循环 */
let reloading = false;

/** 刷新一次（去重：用户点了确定之后可能同时收到多次 controllerchange） */
function reloadOnce(): void {
  if (reloading) return;
  reloading = true;
  window.location.reload();
}

/** 注册 Service Worker，并监听「新版本已装好、正等着接管」的信号 */
export function registerServiceWorker(): void {
  if (!('serviceWorker' in navigator)) return;

  // 进页面时是否已被某个 SW 控制：false = 这是首次安装，装完直接生效，不需要提示也不需要刷新
  const hadController = Boolean(navigator.serviceWorker.controller);

  // 用户确认后新 SW 才 skipWaiting 接管本页；这一刻刷新才能真的拿到新构建
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (hadController) reloadOnce();
  });

  window.addEventListener('load', () => {
    void (async () => {
      try {
        const registration = await navigator.serviceWorker.register(`/sw.js?v=${__BUILD_ID__}`);

        /**
         * 新版本已装好 → 问用户要不要立刻接管。
         * 只在本页已被 SW 控制时提示（首次安装装完即生效，没什么可刷新的）。
         * 用户点「取消」就什么都不做：新 SW 留在 waiting，旧 SW 继续伺候本页，
         * 下一次发布或下次打开页面再问。
         */
        const askTakeover = (worker: ServiceWorker) => {
          if (worker.state !== 'installed') return;
          if (!navigator.serviceWorker.controller) return;
          if (!window.confirm('有新版本，点确定立即刷新')) return;
          // 交给 sw.js 的 message 监听 → skipWaiting → controllerchange → reloadOnce
          worker.postMessage({ type: 'SKIP_WAITING' });
        };

        // 上次可能已经装好一个在 waiting（用户当时点了取消），这次进来再问一次
        if (registration.waiting) askTakeover(registration.waiting);

        registration.addEventListener('updatefound', () => {
          const installing = registration.installing;
          if (!installing) return;

          installing.addEventListener('statechange', () => {
            // installed 且本页已被 SW 控制 = 这是一次更新（而不是首次安装）
            askTakeover(installing);
          });
        });
      } catch {
        // 注册失败（隐私模式 / 浏览器不支持）不影响正常使用
      }
    })();
  });
}
