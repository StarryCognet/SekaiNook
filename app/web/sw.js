// SekaiNook · 旧 Service Worker 退役脚本
//
// 背景：2026-10 网页端主域名从 React 换成 Flutter Web。家里人浏览器里可能还留着
// React 版注册的 Service Worker —— 它缓存过旧页面，会把人挡在旧版本上，而且因为
// 现在 `/sw.js` 已经不再是它熟悉的那份脚本、更新会失败，这个旧 SW 会一直活着。
//
// Flutter 自己用的是 `flutter_service_worker.js`，不会注册这个文件。这个文件存在的
// 唯一目的，就是让那些旧 SW 在下次检查更新时拿到它、装上、清空所有缓存、注销自己，
// 然后让所有打开的页面重新加载一次。
//
// 确认线上再没人带旧 SW 之后（比如几周后），这个文件可以删掉。

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      try {
        const keys = await caches.keys();
        await Promise.all(keys.map((key) => caches.delete(key)));
      } catch (err) {
        // 清缓存失败不该挡住注销
      }
      await self.registration.unregister();
      const clients = await self.clients.matchAll({ type: 'window' });
      for (const client of clients) {
        try {
          await client.navigate(client.url);
        } catch (err) {
          // 有些客户端不允许被导航，忽略
        }
      }
    })(),
  );
});

// 不注册 fetch 监听 —— 让请求直接走网络，避免把旧缓存行为带进新版本。
