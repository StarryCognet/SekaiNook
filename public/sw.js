/* ==========================================================================
 * SekaiNook Service Worker
 * --------------------------------------------------------------------------
 * 纯 JavaScript，无构建步骤（直接由 public/ 原样发布到站点根目录 /sw.js）。
 *
 * 缓存策略总览：
 *   1. 非 GET 请求（POST/PUT/DELETE…）→ 一律不拦截，直接走网络
 *   2. 跨域请求                        → 一律不拦截
 *   3. /api/ 开头的请求                → 永不缓存，直接走网络（数据必须实时）
 *   4. 导航请求（mode === 'navigate'） → network-first，断网回退缓存的 /index.html
 *   5. 同源静态资源（js/css/图片/字体/webmanifest）→ cache-first + 运行时写入缓存
 * ========================================================================== */

/**
 * 构建标识：注册时由 /sw.js?v=<构建标识> 传入（见 src/utils/swUpdate.ts 与
 * vite.config.ts 注入的 __BUILD_ID__）。每次发布它都会变，于是缓存名随之变化，
 * activate 阶段按 CACHE_PREFIX 把上一代缓存整批清掉。
 * 直接访问 /sw.js（没有 ?v=，例如浏览器主动发起的更新检查）时回退为 v1。
 */
const BUILD_ID = new URL(self.location.href).searchParams.get('v') || 'v1';

/**
 * 缓存版本号：直接取构建标识（不再手改）。
 * 注意不要再拼 CACHE_PREFIX——CACHE_NAME 已经会在下面拼一次，重复拼会得到
 * sekainook-sekainook-xxx 这种双前缀。
 */
const CACHE_VERSION = BUILD_ID;

/** 缓存名前缀：activate 阶段按此前缀清理旧版本缓存 */
const CACHE_PREFIX = 'sekainook-';

/** 当前生效的缓存名，例如 sekainook-m1abcd23 */
const CACHE_NAME = CACHE_PREFIX + CACHE_VERSION;

/** Service Worker 自身路径：绝不缓存它，否则浏览器永远拿不到新版本 */
const SW_PATH = '/sw.js';

/** 安装时预缓存的核心文件（保证断网至少能打开界面外壳） */
const PRECACHE_URLS = [
  '/',
  '/index.html',
  '/manifest.webmanifest',
  '/icon.svg',
  '/icon-192.png',
  '/icon-512.png',
  '/apple-touch-icon.png',
];

/** 按 request.destination 判定"静态资源"的白名单 */
const STATIC_DESTINATIONS = ['script', 'style', 'image', 'font', 'manifest'];

/** 按扩展名兜底判定（应对 destination 为空或 'other' 的情况） */
const STATIC_EXT_RE =
  /\.(?:js|mjs|css|png|jpe?g|gif|svg|webp|avif|ico|woff2?|ttf|otf|eot|webmanifest)$/i;

/* --------------------------------------------------------------------------
 * 工具函数
 * ------------------------------------------------------------------------ */

/**
 * 预热构建产物：index.html 里引用的 /assets/xxx.[hash].js|css
 * 只靠预缓存 index.html 是不够的——那些带 hash 的产物必须一起进缓存，
 * 断网时页面才真的能跑起来。整体包在 try/catch 里，任何异常都不影响安装。
 */
async function warmBuildAssets(cache) {
  try {
    const cached = await cache.match('/index.html');
    if (!cached) return;

    const html = await cached.clone().text();
    const urls = new Set();
    const re = /(?:src|href)\s*=\s*"([^"]+)"/g;
    let match;
    while ((match = re.exec(html)) !== null) {
      const raw = match[1];
      if (!raw.startsWith('/')) continue; // 跳过外链、data: 之类
      if (raw.startsWith('/api/')) continue; // 接口数据永不缓存
      if (raw === SW_PATH) continue; // 不缓存 SW 自己
      urls.add(raw);
    }

    await Promise.allSettled(Array.from(urls, (url) => cache.add(url)));
  } catch {
    /* 预热失败不影响 Service Worker 安装 */
  }
}

/** 判断是否属于"同源静态资源"，是的话走 cache-first */
function isStaticAsset(request, url) {
  if (url.pathname === SW_PATH) return false; // SW 自身永远直连网络
  if (STATIC_DESTINATIONS.indexOf(request.destination) !== -1) return true;
  return STATIC_EXT_RE.test(url.pathname);
}

/**
 * 导航请求：network-first。
 * 在线时用最新页面覆盖缓存的 /index.html，断网时回退到它。
 */
async function handleNavigate(request) {
  try {
    const response = await fetch(request);
    if (response && response.ok && response.type === 'basic') {
      const cache = await caches.open(CACHE_NAME);
      await cache.put('/index.html', response.clone());
    }
    return response;
  } catch {
    const cache = await caches.open(CACHE_NAME);
    const fallback =
      (await cache.match('/index.html')) || (await cache.match('/'));
    if (fallback) return fallback;

    return new Response('当前离线，且本地还没有可用的缓存页面。', {
      status: 503,
      statusText: 'Offline',
      headers: { 'Content-Type': 'text/plain; charset=utf-8' },
    });
  }
}

/** 同源静态资源：cache-first，未命中则走网络并写入缓存 */
async function handleStatic(request) {
  const cache = await caches.open(CACHE_NAME);
  const cached = await cache.match(request);
  if (cached) return cached;

  try {
    const response = await fetch(request);
    // 只缓存同源、成功、非 opaque 的响应；带 hash 的产物天然适合长缓存
    if (response && response.ok && response.type === 'basic') {
      await cache.put(request, response.clone());
    }
    return response;
  } catch {
    // 断网且没有缓存：交给浏览器按失败处理
    return Response.error();
  }
}

/* --------------------------------------------------------------------------
 * 生命周期
 * ------------------------------------------------------------------------ */

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE_NAME);

      // 逐个预缓存：单个资源失败不阻塞整体安装
      await Promise.allSettled(
        PRECACHE_URLS.map((url) => cache.add(new Request(url, { cache: 'reload' })))
      );

      // 再把 index.html 引用的构建产物一并缓存，做到"装完即可离线"
      await warmBuildAssets(cache);

      // 新版本立即进入 waiting → activating，不等待旧页面关闭
      await self.skipWaiting();
    })()
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      // 清理所有旧版本缓存（同前缀但不是当前版本）
      const keys = await caches.keys();
      await Promise.all(
        keys
          .filter((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME)
          .map((key) => caches.delete(key))
      );

      // 立即接管未被控制的页面
      await self.clients.claim();
    })()
  );
});

/* --------------------------------------------------------------------------
 * 请求拦截
 * ------------------------------------------------------------------------ */

self.addEventListener('fetch', (event) => {
  const request = event.request;

  // 1. 非 GET 一律不拦截
  if (request.method !== 'GET') return;

  const url = new URL(request.url);

  // 2. 跨域请求不拦截
  if (url.origin !== self.location.origin) return;

  // 3. 接口请求永不缓存，直接走网络
  if (url.pathname.startsWith('/api/')) return;

  // 4. 导航请求：network-first + 回退 /index.html
  if (request.mode === 'navigate') {
    event.respondWith(handleNavigate(request));
    return;
  }

  // 5. 同源静态资源：cache-first
  if (isStaticAsset(request, url)) {
    event.respondWith(handleStatic(request));
  }
});
