/**
 * 本地数据库兜底层（localStorage 持久化）
 *
 * 提供与 Supabase 查询构建器兼容的 API（.from().select().eq().in().order()
 * .single().maybeSingle().insert().update().delete()），
 * 使应用在未配置 Supabase 时也能完整运行。
 *
 * 数据以 JSON 存储在 localStorage，key 前缀为 `sekainook_db_`。
 */

const DB_PREFIX = 'sekainook_db_';

/** 生成简易 uuid */
function genId(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) {
    return crypto.randomUUID();
  }
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

/** 读取表数据 */
function readTable<T>(table: string): T[] {
  try {
    const raw = localStorage.getItem(DB_PREFIX + table);
    return raw ? (JSON.parse(raw) as T[]) : [];
  } catch {
    return [];
  }
}

/** 写入表数据 */
function writeTable<T>(table: string, rows: T[]): void {
  localStorage.setItem(DB_PREFIX + table, JSON.stringify(rows));
}

/** 查询构建器返回的错误对象 */
export interface DbError {
  message: string;
}

/** 查询构建器返回的结果 */
export interface DbResult<T> {
  data: T | null;
  error: DbError | null;
}

/** 排序字段 */
interface OrderSpec {
  column: string;
  ascending: boolean;
}

/** 查询构建器：链式调用，最终通过 await 触发执行 */
class QueryBuilder<T = any> {
  private filters: Array<(row: any) => boolean> = [];
  private orders: OrderSpec[] = [];
  private mode: 'many' | 'single' | 'maybeSingle' = 'many';
  private insertData: Partial<T> | null = null;
  private updateData: Partial<T> | null = null;
  private isDelete = false;

  constructor(private table: string) {}

  /** 选择字段（本地实现忽略，始终返回完整行） */
  select(_columns = '*'): this {
    return this;
  }

  /** 等值过滤 */
  eq(column: string, value: unknown): this {
    this.filters.push((row) => row[column] === value);
    return this;
  }

  /** IN 过滤 */
  in(column: string, values: unknown[]): this {
    this.filters.push((row) => values.includes(row[column]));
    return this;
  }

  /** 排序 */
  order(column: string, opts?: { ascending?: boolean }): this {
    this.orders.push({ column, ascending: opts?.ascending ?? true });
    return this;
  }

  /** 单条（无匹配报错） */
  single(): this {
    this.mode = 'single';
    return this;
  }

  /** 单条（无匹配返回 null） */
  maybeSingle(): this {
    this.mode = 'maybeSingle';
    return this;
  }

  /** 插入 */
  insert(data: Partial<T>): this {
    this.insertData = data;
    return this;
  }

  /** 更新 */
  update(data: Partial<T>): this {
    this.updateData = data;
    return this;
  }

  /** 删除 */
  delete(): this {
    this.isDelete = true;
    return this;
  }

  /** 执行查询（await 时触发） */
  then<TResult1 = DbResult<T[] | T | null>, TResult2 = never>(
    onfulfilled?: ((value: DbResult<T[] | T | null>) => TResult1 | PromiseLike<TResult1>) | null,
    onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null
  ): Promise<TResult1 | TResult2> {
    const result = this.execute();
    return result.then(onfulfilled, onrejected);
  }

  /** 实际执行 */
  private async execute(): Promise<DbResult<T[] | T | null>> {
    try {
      const rows = readTable<T>(this.table);

      // 插入
      if (this.insertData) {
        const now = new Date().toISOString();
        const newRow = {
          ...this.insertData,
          id: (this.insertData as any).id ?? genId(),
          created_at: (this.insertData as any).created_at ?? now,
        } as T;
        writeTable(this.table, [...rows, newRow]);
        return { data: newRow, error: null };
      }

      // 更新
      if (this.updateData) {
        const matched = rows.filter((r) => this.filters.every((f) => f(r)));
        if (matched.length === 0) {
          return { data: null, error: { message: '未找到匹配记录' } };
        }
        const updatedRows = rows.map((r) =>
          this.filters.every((f) => f(r)) ? { ...r, ...this.updateData } : r
        );
        writeTable(this.table, updatedRows);
        const updated = updatedRows.filter((r) => this.filters.every((f) => f(r)));
        return { data: updated.length === 1 ? updated[0] : updated, error: null };
      }

      // 删除
      if (this.isDelete) {
        const remaining = rows.filter((r) => !this.filters.every((f) => f(r)));
        writeTable(this.table, remaining);
        return { data: null, error: null };
      }

      // 查询
      let result = rows.filter((r) => this.filters.every((f) => f(r)));

      // 排序（稳定排序，多字段按顺序）
      for (const order of this.orders) {
        result = [...result].sort((a, b) => {
          const av = (a as any)[order.column];
          const bv = (b as any)[order.column];
          if (av === bv) return 0;
          const cmp = av == null ? 1 : bv == null ? -1 : av < bv ? -1 : 1;
          return order.ascending ? cmp : -cmp;
        });
      }

      if (this.mode === 'single') {
        if (result.length === 0) {
          return { data: null, error: { message: '未找到记录' } };
        }
        return { data: result[0], error: null };
      }
      if (this.mode === 'maybeSingle') {
        return { data: result[0] ?? null, error: null };
      }
      return { data: result, error: null };
    } catch (e) {
      return { data: null, error: { message: e instanceof Error ? e.message : '本地数据库错误' } };
    }
  }
}

/** 本地数据库客户端（兼容 supabase.from() 用法） */
export const localDb = {
  from<T = any>(table: string): QueryBuilder<T> {
    return new QueryBuilder<T>(table);
  },
};

/** 清空本地数据库 */
export function clearLocalDb(): void {
  const keys: string[] = [];
  for (let i = 0; i < localStorage.length; i++) {
    const key = localStorage.key(i);
    if (key && key.startsWith(DB_PREFIX)) {
      keys.push(key);
    }
  }
  keys.forEach((k) => localStorage.removeItem(k));
}