#!/usr/bin/env node
/**
 * 给 Flutter Web 的 version.json 补一个「构建时间戳」built_at。
 *
 * 为什么需要：`app/web/flutter_bootstrap.js` 用 version.json 拼 `main.dart.js?v=…`
 * 来绕开 Cloudflare 对 main.dart.js 的 4 小时强缓存。但 `web:build` 不一定升版本号
 * （AGENTS 允许「只发网页版」），如果 ?v= 继续取 `version+build_number`，只发网页版时
 * 这个值不变 → 老访客最多 4 小时还看旧 UI。
 *
 * 每次构建都写一个新的 built_at，URL 必变，缓存自然绕开。
 *
 * 用法（package.json 的 web:build 自动调用）：
 *   node scripts/stamp-web-version.mjs [web产物目录]
 * 默认目录 app/build/web，可用环境变量 SEKAINOOK_WEB_DIR 覆盖。
 */

import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const webDir = resolve(ROOT, process.env.SEKAINOOK_WEB_DIR ?? 'app/build/web');
const versionPath = resolve(webDir, 'version.json');

if (!existsSync(versionPath)) {
  console.error(
    `找不到 ${versionPath} —— 先构建网页版：cd app && flutter build web --release --no-pub`
  );
  process.exit(1);
}

let raw;
try {
  raw = JSON.parse(readFileSync(versionPath, 'utf8'));
} catch (error) {
  console.error(`version.json 不是合法 JSON：${error.message}`);
  process.exit(1);
}

if (!raw || typeof raw !== 'object') {
  console.error('version.json 内容不是对象');
  process.exit(1);
}

// 时间戳同时带上毫秒和可读时间：毫秒保证每次构建不同，可读时间方便人肉核对
const builtAt = `${Date.now()}`;
raw.built_at = builtAt;
raw.built_at_display = new Date().toISOString();

writeFileSync(versionPath, `${JSON.stringify(raw, null, 2)}\n`, 'utf8');
console.log(
  `[stamp] ${versionPath} → version=${raw.version ?? '?'} build=${raw.build_number ?? '?'} built_at=${builtAt}`
);
