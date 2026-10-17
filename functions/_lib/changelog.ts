/**
 * 版本日志（changelog 表）的读取工具。
 *
 * 为什么上云：网页版（本仓库）和 Flutter 版（SekaiNook-App）是两个仓库、各自打包，
 * 版本日志以前各存一份代码常量，改一处另一处不跟着变。现在两端都读 D1 这张表，
 * 谁也不必等对方发版。
 *
 * 和 functions/_lib/settings.ts 的差别（故意不一样）：
 *   settings 的读工具把异常吞掉、回默认值，因为称呼读不到也得让业务继续跑；
 *   这里**把异常抛出去**，由接口转成 ready:false —— 「表没迁移 / 还没播种」必须能被
 *   调用方区分出来，否则两端会拿着一张空表渲染出一片空白，而不是退回自己兜底的那份。
 *
 * 兜底分工：服务端只管读；bundle 里那份 CHANGELOG（src/config/changelog.ts、
 * lib/config/changelog.dart）由客户端在 ready:false 时使用。
 */

/** 一条版本日志（就是界面上要渲染的一行） */
export interface ChangelogEntry {
  /** 版本号，例如 '1.31.0' */
  version: string;
  /** 展示用的时间串，例如 '2026-10-17 22:40:00'（原样透出，不做时区换算） */
  date: string;
  /** 这一版的一句话主题 */
  title: string;
  /** 改动条目；存的是 JSON 数组字符串，这里解析回数组 */
  changes: string[];
}

/** 接口要回的东西 */
export interface ChangelogSnapshot {
  /** 最新一条的版本号；表里没内容时为 null */
  version: string | null;
  /** 按 sort_order 升序 = 最新在前 */
  entries: ChangelogEntry[];
}

/** 一次最多读几条：正常也就几十条，表要是被写坏了也不至于把响应撑大 */
export const MAX_CHANGELOG_ENTRIES = 200;

interface ChangelogRow {
  version: string | null;
  date: string | null;
  title: string | null;
  changes: string | null;
}

/**
 * 把一行的 changes（JSON 数组字符串）解析成字符串数组。
 * 坏数据不抛错：日志是「给人看的历史」，少一条备注不值得让整个接口 500。
 */
function parseChanges(raw: string | null): string[] {
  if (typeof raw !== 'string' || !raw.trim()) return [];
  try {
    const parsed = JSON.parse(raw) as unknown;
    if (!Array.isArray(parsed)) return [];
    return parsed
      .filter((item): item is string => typeof item === 'string')
      .map((item) => item.trim())
      .filter((item) => item.length > 0);
  } catch {
    return [];
  }
}

/** 读全部版本日志（最新在前）；表没迁移时抛错，由接口兜底成 ready:false */
export async function readChangelog(db: D1Database): Promise<ChangelogSnapshot> {
  const result = await db
    .prepare(
      `SELECT version, date, title, changes FROM changelog
        ORDER BY sort_order ASC
        LIMIT ?`
    )
    .bind(MAX_CHANGELOG_ENTRIES)
    .all<ChangelogRow>();

  const entries: ChangelogEntry[] = [];
  for (const row of result.results ?? []) {
    const version = (row.version ?? '').trim();
    // 没有版本号的行渲染不出来（也说明这行是坏的），直接跳过
    if (!version) continue;
    entries.push({
      version,
      date: (row.date ?? '').trim(),
      title: (row.title ?? '').trim(),
      changes: parseChanges(row.changes),
    });
  }

  return { version: entries[0]?.version ?? null, entries };
}
