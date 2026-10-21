{{flutter_js}}
{{flutter_build_config}}

// SekaiNook 自定义引导脚本（覆盖 Flutter 默认生成的 flutter_bootstrap.js）
//
// 目的：给入口 JS（main.dart.js）加版本号 query。
// 背景：Flutter Web 的 main.dart.js 文件名固定不带内容 hash，而 Cloudflare 静态资源
// 默认缓存 4 小时（max-age=14400），发版后老访客会继续拿旧 JS、页面显示的版本号滞后。
// 这里在引导阶段先读 no-cache 的 version.json，把 version+build_number 拼进
// main.dart.js 的 URL —— 每次发版 URL 必变，浏览器与 CDN 都无法命中旧缓存。
(async function () {
  const defaultEntrypoint = 'main.dart.js';
  let entrypoint = defaultEntrypoint;

  try {
    const response = await fetch('version.json', { cache: 'no-store' });
    if (response.ok) {
      const version = await response.json();
      if (version && version.version) {
        const tag = version.version + '-' + (version.build_number || '0');
        entrypoint = defaultEntrypoint + '?v=' + encodeURIComponent(tag);
      }
    }
  } catch (error) {
    // 拿不到 version.json 时退回默认入口，不影响启动。
  }

  const buildConfig = window._flutter && window._flutter.buildConfig;
  if (buildConfig && Array.isArray(buildConfig.builds)) {
    for (const build of buildConfig.builds) {
      // 部分 Flutter 版本不写 mainJsPath，这里显式补齐后再改写。
      build.mainJsPath = entrypoint;
    }
  }

  _flutter.loader.load();
})();
