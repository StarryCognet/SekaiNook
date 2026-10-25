#!/usr/bin/env node
/**
 * 版本日志同步工具（配合 migrations/0006_changelog.sql）。
 *
 * 为什么要有它：版本日志从「两端各存一份代码常量」改成「D1 里一份、两端都读」之后，
 * 代码里那份 src/config/changelog.ts 的身份变成**播种数据 + 兜底**，于是需要一个口子
 * 把它推上库。这个脚本就是这个口子，做两件事：
 *
 *   sync      读 src/config/changelog.ts → 生成 SQL → 交给 wrangler d1 execute
 *   fallback  读 src/config/changelog.ts → 生成 app/ 里那份兜底（app/lib/config/changelog.dart）
 *
 * 为什么是「UPSERT + 删多余」而不是「先清空再灌」：
 *   两条语句之间有一个空窗，这时候正好有人打开设置页，就会看到空日志（虽然会退回兜底，
 *   但没必要制造这个窗口）；另外万一第二条失败，库里还是完整的旧数据而不是空的。
 *
 * 用法：
 *   npm run changelog:sync               # 同步到线上库（部署前跑）
 *   npm run changelog:sync -- --local    # 同步到本地库（wrangler pages dev 时用）
 *   npm run changelog:sync -- --dry      # 只生成 SQL、打印命令，不真的写库
 *   npm run changelog:fallback           # 重新生成 app/ 里那份兜底
 *   npm run changelog:fallback -- --check # 只检查有没有漂移（不写文件，漂移则退出码 1）
 *
 * 环境变量：
 *   SEKAINOOK_DB   D1 库名，默认 sekainook（见 wrangler.jsonc 的 d1_databases）
 *   SEKAINOOK_APP  Flutter 目录路径，默认仓库内的 app/（指到别处仍可用它覆盖）
 */

import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
/** 生成的 SQL 落在仓库里（不是临时目录）：wrangler 跑不动时可以直接手动执行它 */
const SQL_PATH = resolve(ROOT, 'migrations/.changelog-sync.sql');
const CHANGELOG_TS = resolve(ROOT, 'src/config/changelog.ts');
const DB_NAME = process.env.SEKAINOOK_DB ?? 'sekainook';
const APP_DIR = process.env.SEKAINOOK_APP ?? resolve(ROOT, 'app');
const DART_PATH = resolve(APP_DIR, 'lib/config/changelog.dart');

/* ---------------------------------- 读取 ---------------------------------- */

/** 读 src/config/changelog.ts（Node 24 自带 TS 类型擦除，直接 import 即可） */
async function loadChangelog() {
  const mod = await import(pathToFileURL(CHANGELOG_TS).href);
  return { version: String(mod.APP_VERSION ?? ''), entries: mod.CHANGELOG };
}

/**
 * 校验清单：这里挡的都是「同步出去会很难查」的错，宁可在本地吵一次。
 * 尤其 date —— 版本日志的日期必须是真实的，历史上就因为随手写日期返工过。
 */
function assertEntries(entries, appVersion) {
  const problems = [];
  if (!Array.isArray(entries) || entries.length === 0) {
    fail(['src/config/changelog.ts 里的 CHANGELOG 是空的']);
  }

  const seen = new Set();
  entries.forEach((entry, index) => {
    const where = `第 ${index + 1} 条`;
    if (typeof entry?.version !== 'string' || !entry.version.trim()) {
      problems.push(`${where}没有 version`);
      return;
    }
    if (seen.has(entry.version)) problems.push(`版本号重复：${entry.version}`);
    seen.add(entry.version);

    if (typeof entry.date !== 'string' || !/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(entry.date)) {
      problems.push(`${entry.version}: date 必须是 'YYYY-MM-DD HH:mm:ss'，现在是 ${JSON.stringify(entry.date)}`);
    } else {
      // R-7：形状对不代表日期存在 —— 2026-02-30 会被 Date 悄悄进位成 3 月 2 日，
      // 写进 D1 后两端都会显示一个「不存在的日期」。
      const [datePart, timePart] = entry.date.split(' ');
      const [year, month, day] = datePart.split('-').map(Number);
      const [hour, minute, second] = timePart.split(':').map(Number);
      const parsed = new Date(year, month - 1, day, hour, minute, second);
      const real =
        parsed.getFullYear() === year &&
        parsed.getMonth() === month - 1 &&
        parsed.getDate() === day &&
        parsed.getHours() === hour &&
        parsed.getMinutes() === minute &&
        parsed.getSeconds() === second;
      if (!real) problems.push(`${entry.version}: date ${entry.date} 不是一个真实存在的时间`);
    }
    if (typeof entry.title !== 'string' || !entry.title.trim()) {
      problems.push(`${entry.version}: title 不能为空`);
    }
    if (!Array.isArray(entry.changes) || entry.changes.length === 0) {
      problems.push(`${entry.version}: changes 至少要有一条`);
    } else if (entry.changes.some((item) => typeof item !== 'string' || !item.trim())) {
      problems.push(`${entry.version}: changes 里有空条目或非字符串`);
    }
  });

  if (appVersion !== entries[0].version) {
    problems.push(
      `APP_VERSION（${appVersion}）和最新一条日志（${entries[0].version}）对不上 —— 两者必须一致，兜底页面显示的就是 APP_VERSION`
    );
  }

  // R-8：三方一致 —— APK 的 versionName 来自 app/pubspec.yaml，网页版读的是
  // D1 里的 APP_VERSION，两边漂移就会出现「APK 说 2.7.0、网站说 2.6.0」。
  try {
    const pubspec = readFileSync(resolve(APP_DIR, 'pubspec.yaml'), 'utf8');
    const match = pubspec.match(/^version:\s*(\S+)/m);
    const pubVersion = match?.[1]?.split('+')[0];
    if (!pubVersion) {
      problems.push('app/pubspec.yaml 里没找到 version: 行');
    } else if (pubVersion !== appVersion) {
      problems.push(
        `app/pubspec.yaml 的版本（${pubVersion}）和 APP_VERSION（${appVersion}）对不上 —— 发版前先把两边对齐（记得 +N 一起加）`
      );
    }
  } catch (error) {
    problems.push(`读不到 app/pubspec.yaml：${error instanceof Error ? error.message : String(error)}`);
  }

  if (problems.length > 0) fail(problems);
  return entries;
}

/* -------------------------------- SQL 生成 -------------------------------- */

/** SQL 字符串字面量：单引号翻倍（SQL 里就是这个规矩） */
function sqlLiteral(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}

function buildSql(entries) {
  const updatedAt = new Date().toISOString();
  const lines = [
    '-- 由 scripts/changelog-sync.mjs 生成（内容源：src/config/changelog.ts），请勿手改。',
    `-- 生成时间：${updatedAt}，共 ${entries.length} 条`,
    `-- 手动执行：npx wrangler d1 execute ${DB_NAME} --remote --file=migrations/.changelog-sync.sql`,
    '',
  ];

  entries.forEach((entry, index) => {
    lines.push(
      'INSERT INTO changelog (version, date, title, changes, sort_order, updated_at) VALUES (' +
        `${sqlLiteral(entry.version)}, ${sqlLiteral(entry.date)}, ${sqlLiteral(entry.title)}, ` +
        `${sqlLiteral(JSON.stringify(entry.changes))}, ${index}, ${sqlLiteral(updatedAt)})`,
      'ON CONFLICT(version) DO UPDATE SET date = excluded.date, title = excluded.title, ' +
        'changes = excluded.changes, sort_order = excluded.sort_order, updated_at = excluded.updated_at;'
    );
  });

  // 代码里删掉（改版本号 / 撤回）的那些，库里也要跟着消失，否则两端会看到幽灵版本
  lines.push(
    '',
    `DELETE FROM changelog WHERE version NOT IN (${entries.map((entry) => sqlLiteral(entry.version)).join(', ')});`
  );
  return `${lines.join('\n')}\n`;
}

/* --------------------------------- Dart ---------------------------------- */

/** Dart 单引号字符串字面量（反斜杠先转，再转引号和 $，否则会翻转义） */
function dartLiteral(value) {
  const escaped = String(value)
    .replace(/\\/g, '\\\\')
    .replace(/'/g, "\\'")
    .replace(/\$/g, '\\$')
    .replace(/\r/g, '\\r')
    .replace(/\n/g, '\\n')
    .replace(/\t/g, '\\t');
  return `'${escaped}'`;
}

/** 把 dartLiteral 的结果还原回去：生成完自校验一遍，转义写错当场就报 */
function undartLiteral(literal) {
  const body = literal.slice(1, -1);
  let out = '';
  for (let i = 0; i < body.length; i++) {
    const ch = body[i];
    if (ch !== '\\') {
      out += ch;
      continue;
    }
    const next = body[++i];
    if (next === 'n') out += '\n';
    else if (next === 'r') out += '\r';
    else if (next === 't') out += '\t';
    else out += next;
  }
  return out;
}

function buildDart(appVersion, entries) {
  // 注意：这段是模板字符串，里面的反引号要写成 \` —— 所以干脆用「」当引号，少一层转义
  const header = `/// 版本历史与应用版本号（由 Web 仓库的 src/config/changelog.ts 生成）。
///
/// 生成方式：在 SekaiNook 仓库里跑 \`npm run changelog:fallback\`。
/// 别手改这个文件；要加版本日志请改 Web 仓库那份，再生成 + 同步。
///
/// 正常路径下设置页读的是云端 GET /api/changelog（网页版和 App 看同一份）；
/// 这份只在读不到云端时兜底（表没迁移 / 还没同步 / 断网）。
class ChangelogEntry {
  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.title,
    required this.changes,
  });

  /// 版本号，例如 1.31.0
  final String version;

  /// 发布日期，例如 2026-10-17 22:40:00
  final String date;

  /// 这一版的一句话主题
  final String title;

  /// 改动条目
  final List<String> changes;
}

/// 当前版本号（与 [changelog] 第一条保持一致）。
const String appVersion = ${dartLiteral(appVersion)};

/// 版本历史（倒序：最新在前）。
const List<ChangelogEntry> changelog = <ChangelogEntry>[
`;

  const body = entries
    .map((entry) =>
      [
        '  ChangelogEntry(',
        `    version: ${dartLiteral(entry.version)},`,
        `    date: ${dartLiteral(entry.date)},`,
        `    title: ${dartLiteral(entry.title)},`,
        ...changesBlock(entry.changes),
        '  ),',
      ].join('\n')
    )
    .join('\n');

  return `${header}${body}\n];\n`;
}

/**
 * `changes:` 那几行。dart format 对集合的规矩是「一行放得下就收成一行，否则一项一行」，
 * 这里照着来 —— 生成物本身就是格式化好的，别人再跑 dart format 不会看到一整屏 diff。
 */
function changesBlock(changes) {
  const items = changes.map((change) => dartLiteral(change));
  const oneLine = `    changes: <String>[${items.join(', ')}],`;
  if (oneLine.length <= 80) return [oneLine];
  return ['    changes: <String>[', ...items.map((item) => `      ${item},`), '    ],'];
}

/** 自校验：生成的每个字面量都要能原样还原，否则说明转义写错了 */
function verifyDartRoundTrip(appVersion, entries) {
  const samples = [appVersion];
  for (const entry of entries) {
    samples.push(entry.version, entry.date, entry.title, ...entry.changes);
  }
  for (const sample of samples) {
    if (undartLiteral(dartLiteral(sample)) !== sample) {
      fail([`Dart 字面量转义自校验失败：${JSON.stringify(sample)}`]);
    }
  }
}

/* --------------------------------- 动作 ---------------------------------- */

function runSync(argv) {
  const target = argv.includes('--local') ? 'local' : 'remote';
  const dryRun = argv.includes('--dry');
  const extra = argv.filter((arg) => !['--local', '--remote', '--dry'].includes(arg));

  return loadChangelog().then(({ version, entries }) => {
    assertEntries(entries, version);
    const sql = buildSql(entries);
    writeFileSync(SQL_PATH, sql, 'utf8');

    const command = [
      'npx',
      'wrangler',
      'd1',
      'execute',
      DB_NAME,
      `--${target}`,
      '--file=migrations/.changelog-sync.sql',
      ...extra,
    ].join(' ');

    console.log(`已生成 ${SQL_PATH}（${entries.length} 条，最新 v${version}）`);
    console.log(`目标：${target === 'local' ? '本地库' : '线上库'}`);

    if (dryRun) {
      console.log(`--dry：不执行。要真的写库就跑：\n${command}`);
      return 0;
    }

    console.log(`执行：${command}`);
    const result = spawnSync(command, { cwd: ROOT, stdio: 'inherit', shell: true });
    if (result.status !== 0) {
      console.error(
        `\nwrangler 没跑成功（退出码 ${result.status}）。SQL 已经生成好了，可以手动执行：\n${command}`
      );
      return result.status ?? 1;
    }
    console.log('同步完成。自检里的 env.changelog 应该变成 ok。');
    return 0;
  });
}

function runFallback(argv) {
  const checkOnly = argv.includes('--check');
  return loadChangelog().then(({ version, entries }) => {
    assertEntries(entries, version);
    verifyDartRoundTrip(version, entries);
    const dart = buildDart(version, entries);

    if (checkOnly) {
      if (!existsSync(DART_PATH)) {
        console.error(`找不到 ${DART_PATH}（用 SEKAINOOK_APP 指定 App 仓库路径）`);
        return 1;
      }
      const current = readFileSync(DART_PATH, 'utf8');
      if (current !== dart) {
        console.error(`${DART_PATH} 和 Web 仓库的版本日志不一致，跑 npm run changelog:fallback 重新生成`);
        return 1;
      }
      console.log(`${DART_PATH} 与 Web 仓库一致（${entries.length} 条，最新 v${version}）`);
      return 0;
    }

    writeFileSync(DART_PATH, dart, 'utf8');
    console.log(`已生成 ${DART_PATH}（${entries.length} 条，最新 v${version}）`);
    return 0;
  });
}

/* --------------------------------- 入口 ---------------------------------- */

function fail(problems) {
  console.error('版本日志自检没过：');
  for (const problem of problems) console.error(`  * ${problem}`);
  process.exit(1);
}

const [action, ...argv] = process.argv.slice(2);

const run = async () => {
  switch (action) {
    case 'sync':
      return runSync(argv);
    case 'fallback':
      return runFallback(argv);
    default:
      console.error('用法：node scripts/changelog-sync.mjs <sync|fallback> [--local|--dry|--check]');
      return 1;
  }
};

run()
  .then((code) => {
    process.exit(code ?? 0);
  })
  .catch((error) => {
    console.error('同步失败：', error);
    process.exit(1);
  });
