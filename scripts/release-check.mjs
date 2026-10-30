#!/usr/bin/env node
/**
 * 发布一致性检查：一次把「这次要不要发、发到哪一端、线上的和本地的一不一样」看全。
 *
 * 为什么需要（报告 R-2/R-3）：
 *   * 家里人有网页版和 App 两个入口，只发一端就有一半人看旧版，而旧流程里没有任何机器检查；
 *   * 忘了 changelog:sync 时线上版本日志停在旧版本，发 APK 的人也不会被拦住。
 *
 * 检查四组数字是否一致：
 *   1. app/pubspec.yaml 的 version（versionName+buildNumber）
 *   2. src/config/changelog.ts 的 APP_VERSION（且 CHANGELOG 最新一条等于它）
 *   3. 线上 https://sn.starrymiku.com/version.json（网页版实际产物）
 *   4. 线上 https://pub.starrymiku.com/sekainook/latest.json（App 更新清单）
 * 另外读线上 /api/changelog 的最新版本。
 *
 * 用法：
 *   npm run release:check            # 联网核对全部
 *   npm run release:check -- --offline   # 只核对本地两份（pubspec ↔ changelog.ts）
 *   npm run release:check -- --skip-web  # 只核对 App 侧线上清单
 *   npm run release:check -- --skip-apk  # 只核对网页版侧
 *
 * 退出码：0 全一致；1 有差异（输出里会写明是哪一项）。
 */

import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const argv = new Set(process.argv.slice(2));
const offline = argv.has('--offline');
const skipWeb = offline || argv.has('--skip-web');
const skipApk = offline || argv.has('--skip-apk');

const problems = [];
const warnings = [];
const ok = (message) => console.log(`  ✅ ${message}`);
const bad = (message) => {
  problems.push(message);
  console.log(`  ❌ ${message}`);
};
const warn = (message) => {
  warnings.push(message);
  console.log(`  ⚠️  ${message}`);
};

/** 读 app/pubspec.yaml 顶层的 version: x.y.z+N */
function readPubspecVersion() {
  const text = readFileSync(resolve(ROOT, 'app/pubspec.yaml'), 'utf8');
  const match = text.match(/^version:\s*([0-9][^\s#]*)/m);
  if (!match) throw new Error('app/pubspec.yaml 里找不到 version: 行');
  const raw = match[1].trim();
  const [versionName, buildNumber = '0'] = raw.split('+');
  return { raw, versionName, buildNumber };
}

async function readLocalChangelog() {
  const mod = await import(pathToFileURL(resolve(ROOT, 'src/config/changelog.ts')).href);
  const appVersion = String(mod.APP_VERSION ?? '');
  const entries = Array.isArray(mod.CHANGELOG) ? mod.CHANGELOG : [];
  return { appVersion, latest: entries[0] ?? null, count: entries.length };
}

async function fetchJson(url, label) {
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(15000) });
    if (!response.ok) {
      bad(`${label}：HTTP ${response.status}（${url}）`);
      return null;
    }
    return await response.json();
  } catch (error) {
    bad(`${label}：读取失败 ${error.message}（${url}）`);
    return null;
  }
}

console.log('SekaiNook 发布一致性检查\n');

// ---- 1. 本地两份：pubspec ↔ changelog.ts ----
console.log('[1/4] 本地版本号');
const pubspec = readPubspecVersion();
const changelog = await readLocalChangelog();
console.log(
  `  本地：pubspec=${pubspec.versionName}+${pubspec.buildNumber}，changelog.ts=${changelog.appVersion}（${changelog.count} 条）`
);
if (pubspec.versionName !== changelog.appVersion) {
  bad(`pubspec 的 ${pubspec.versionName} 与 changelog.ts 的 ${changelog.appVersion} 不一致`);
} else {
  ok('pubspec 与 changelog.ts 的版本号一致');
}
if (changelog.latest && changelog.latest.version !== changelog.appVersion) {
  bad(`CHANGELOG 最新一条是 v${changelog.latest.version}，但 APP_VERSION 是 ${changelog.appVersion}`);
} else if (changelog.latest) {
  ok(`CHANGELOG 最新一条 v${changelog.latest.version} 与 APP_VERSION 一致`);
}

// ---- 2. 线上网页版产物 ----
console.log('\n[2/4] 线上网页版（version.json）');
if (skipWeb) {
  warn('跳过（--offline / --skip-web）');
} else {
  const versionJson = await fetchJson(
    'https://sn.starrymiku.com/version.json',
    '线上 version.json'
  );
  if (versionJson) {
    const remote = {
      versionName: String(versionJson.version ?? ''),
      buildNumber: String(versionJson.build_number ?? '0'),
    };
    console.log(`  线上：${remote.versionName}+${remote.buildNumber}，built_at=${versionJson.built_at ?? '（旧产物没有时间戳）'}`);
    if (remote.versionName !== pubspec.versionName || remote.buildNumber !== pubspec.buildNumber) {
      bad(
        `网页版产物是 ${remote.versionName}+${remote.buildNumber}，本地是 ${pubspec.versionName}+${pubspec.buildNumber} —— 网页版还没发布最新版？`
      );
    } else {
      ok('网页版产物版本与本地一致');
    }
    if (!versionJson.built_at) {
      warn('线上 version.json 没有 built_at：网页版还是旧构建（下次 web:deploy 会带上）');
    }
  }
}

// ---- 3. 线上 App 更新清单 ----
console.log('\n[3/4] 线上 App 清单（latest.json）');
if (skipApk) {
  warn('跳过（--offline / --skip-apk）');
} else {
  const latest = await fetchJson(
    'https://pub.starrymiku.com/sekainook/latest.json',
    '线上 latest.json'
  );
  if (latest) {
    const remoteName = String(latest.versionName ?? '');
    const remoteCode = String(latest.versionCode ?? '');
    console.log(`  线上：${remoteName}(${remoteCode})`);
    if (remoteName !== pubspec.versionName || remoteCode !== pubspec.buildNumber) {
      bad(
        `App 清单是 ${remoteName}(${remoteCode})，本地是 ${pubspec.versionName}(${pubspec.buildNumber}) —— 再跑一次 publish_apk.ps1？`
      );
    } else {
      ok('App 清单版本与本地一致');
    }
  }
}

// ---- 4. 线上版本日志 ----
console.log('\n[4/4] 线上版本日志（/api/changelog）');
if (offline) {
  warn('跳过（--offline）');
} else {
  const api = await fetchJson('https://sn.starrymiku.com/api/changelog', '线上 /api/changelog');
  if (api) {
    const remoteVersion = api.version == null ? null : String(api.version);
    console.log(`  线上：${remoteVersion ?? '（空，未同步）'}（ready=${api.ready}）`);
    if (remoteVersion !== changelog.appVersion) {
      bad(
        `线上版本日志是 ${remoteVersion ?? '空'}，本地是 ${changelog.appVersion} —— 先跑 npm run changelog:sync（接口缓存 5 分钟，刚同步完可以等一会再查）`
      );
    } else {
      ok('线上版本日志与本地一致');
    }
  }
}

// ---- 结论 ----
console.log('');
if (warnings.length > 0) {
  console.log(`⚠️  ${warnings.length} 条警告（不阻断）：`);
  for (const message of warnings) console.log(`   - ${message}`);
}
if (problems.length > 0) {
  console.log(`\n❌ 发现 ${problems.length} 个不一致：`);
  for (const message of problems) console.log(`   - ${message}`);
  console.log('\n修完再发：本地版本先改 pubspec.yaml + changelog.ts，再 changelog:sync，最后发两端。');
  process.exit(1);
}
console.log('✅ 全部一致 —— 可以发版/已发完。');
