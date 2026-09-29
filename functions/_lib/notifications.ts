/**
 * 通知收件箱的写入工具（供 ledger 等业务接口调用）。
 *
 * 路由说明：Pages Functions 会忽略下划线开头的路径，本文件不会被当成接口暴露；
 * 真正的接口在 functions/api/notifications/ 下。
 *
 * 设计原则：记账/审批是主业务，通知是附加品 —— 写通知失败绝不能影响主流程，
 * 因此 pushNotifications 内部吞掉异常，只往日志里打一行。
 */

/** 没有账号体系，就用两格信箱 */
export type NotifyAudience = 'parent' | 'child';

export interface NotificationInput {
  audience: NotifyAudience;
  /** 事件类型：checkin_pending | approved | rejected | resubmitted | recorded | payout */
  type: string;
  title: string;
  body?: string | null;
  /** 点击后跳到哪儿，如 /family */
  link?: string | null;
  /** 幂等键：同键只保留第一条；不传则每次都会写 */
  dedupeKey?: string | null;
}

const AUDIENCES: readonly string[] = ['parent', 'child'];

/** 截断保护，避免脏数据撑爆界面 */
function clip(value: unknown, max: number): string | null {
  if (typeof value !== 'string') return null;
  const text = value.trim();
  return text ? text.slice(0, max) : null;
}

/** 积分文本统一在这里拼：收入 +10、支出 -10 */
export function amountText(type: string, amount: number): string {
  const sign = type === 'spending' ? '-' : '+';
  return `${sign}${Math.abs(amount)}`;
}

/** 批量写入通知；任何异常都只记日志，不向上抛 */
export async function pushNotifications(
  db: D1Database,
  items: readonly NotificationInput[]
): Promise<void> {
  const rows = items.filter((item) => AUDIENCES.includes(item.audience));
  if (rows.length === 0) return;

  const createdAt = new Date().toISOString();

  try {
    // D1 单次 batch 上限 100 条；调用方一次最多传几条，这里只做兜底切片
    await db.batch(
      rows.slice(0, 20).map((item) =>
        db
          .prepare(
            `INSERT OR IGNORE INTO notifications
               (id, audience, type, title, body, link, dedupe_key, status, created_at, read_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, 'unread', ?, NULL)`
          )
          .bind(
            crypto.randomUUID(),
            item.audience,
            clip(item.type, 40) ?? 'unknown',
            clip(item.title, 120) ?? '',
            clip(item.body, 200),
            clip(item.link, 200),
            clip(item.dedupeKey, 160),
            createdAt
          )
      )
    );
  } catch (error) {
    // 常见原因：库里还没跑 0003 迁移（老库）。记账本身已经成功，这里只留痕。
    console.error('pushNotifications failed', error);
  }
}
