/**
 * D1 兼容层：把 Cloudflare D1 的最小契约映射到本地 SQLite（better-sqlite3）。
 *
 * 只实现 `functions/` 里实际用到的部分（逐条对照过调用点）：
 *   prepare(sql).bind(...).all()   —— 7 处
 *   prepare(sql).bind(...).first() —— 含 `INSERT ... RETURNING` 的 upsert
 *   prepare(sql).bind(...).run()   —— 20 处，判「有没有命中」全靠 result.meta.changes
 *   db.batch([...])                —— 4 处，必须在同一事务里
 *
 * 刻意不实现 raw() / withSession() / 游标分页：仓库里没人用（grep `.raw(` 为 0 次）。
 */
import Database from 'better-sqlite3';
import { mkdirSync } from 'node:fs';
import path from 'node:path';

type Value = string | number | bigint | boolean | null | undefined;

/** D1 的绑定值不接受 boolean：转成 0 / 1 */
function normalize(value: Value): string | number | bigint | null {
  if (value === undefined || value === null) return null;
  if (typeof value === 'boolean') return value ? 1 : 0;
  return value;
}

export class D1Statement {
  private args: (string | number | bigint | null)[] = [];

  constructor(
    private readonly db: Database.Database,
    private readonly sql: string
  ) {}

  bind(...values: Value[]): this {
    this.args = values.map(normalize);
    return this;
  }

  allSync<T = unknown>(): T[] {
    return this.db.prepare(this.sql).all(...this.args) as T[];
  }

  runSync() {
    return this.db.prepare(this.sql).run(...this.args);
  }

  /**
   * batch 里每个元素都必须是 D1Result（含 results 数组）：
   * SELECT → results 是行数组；INSERT/UPDATE → results 为空数组 + meta.changes。
   * 靠 better-sqlite3 的 Statement.reader 区分（RETURNING 也算 reader）。
   */
  executeSync() {
    const statement = this.db.prepare(this.sql);
    if (statement.reader) {
      return { results: statement.all(...this.args), success: true, meta: {} };
    }
    const result = statement.run(...this.args);
    return {
      results: [] as unknown[],
      success: true,
      meta: { changes: result.changes, last_row_id: Number(result.lastInsertRowid) },
    };
  }

  /** D1: { results, success, meta } */
  async all<T = unknown>() {
    return { results: this.allSync<T>(), success: true, meta: {} };
  }

  /** D1: 首行或 null */
  async first<T = unknown>(): Promise<T | null> {
    return (this.db.prepare(this.sql).get(...this.args) ?? null) as T | null;
  }

  /** D1: { meta: { changes } } —— 现有代码全靠 meta.changes 判断「有没有更新到行」 */
  async run() {
    const result = this.runSync();
    return {
      success: true,
      meta: { changes: result.changes, last_row_id: Number(result.lastInsertRowid) },
    };
  }
}

export interface D1Compat {
  prepare(sql: string): D1Statement;
  batch(statements: D1Statement[]): Promise<unknown[]>;
  exec(sql: string): void;
  close(): void;
}

export function createD1(dbPath: string): D1Compat {
  mkdirSync(path.dirname(dbPath), { recursive: true });
  const db = new Database(dbPath);
  // WAL：家庭多设备并发读写不互相阻塞；busy_timeout 兜住瞬时锁竞争
  db.pragma('journal_mode = WAL');
  db.pragma('busy_timeout = 5000');
  db.pragma('foreign_keys = ON');

  return {
    prepare(sql: string) {
      return new D1Statement(db, sql);
    },

    /** D1 的 batch 是一个事务：任何一条失败整体回滚 */
    async batch(statements: D1Statement[]) {
      const runAll = db.transaction((items: D1Statement[]) => items.map((item) => item.executeSync()));
      return runAll(statements);
    },

    exec(sql: string) {
      db.exec(sql);
    },

    close() {
      db.close();
    },
  };
}
