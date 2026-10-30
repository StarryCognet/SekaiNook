/**
 * 运行时环境：Node 版把 Cloudflare 的绑定换成本地实现注入进去。
 *
 * 与 functions/ 里的 `interface Env` 一一对应：
 *   DB                 → better-sqlite3（server/d1.ts）
 *   STARRYMIKU_BUCKET  → 本地目录（server/r2.ts）
 *   ADMIN_PASSWORD     → 环境变量（测试期用单独口令，别复用线上）
 *   VAPID_*            → 留空即可：/api/push/key 会回 ready:false，前端正常降级
 *   REMINDER_URL       → 留空即可：自检里推送类检查预期红，其余照常
 */
import path from 'node:path';
import { createD1 } from './d1';
import { createR2Bucket } from './r2';

export function buildEnv() {
  const root = process.cwd();
  const dbPath = process.env.DB_PATH ?? path.join(root, 'data', 'sekainook.db');
  const r2Dir = process.env.R2_DIR ?? path.join(root, 'data', 'r2');

  return {
    DB: createD1(dbPath),
    STARRYMIKU_BUCKET: createR2Bucket(r2Dir),
    ADMIN_PASSWORD: process.env.ADMIN_PASSWORD ?? '',
    VAPID_PUBLIC_KEY: process.env.VAPID_PUBLIC_KEY ?? '',
    VAPID_SUBJECT: process.env.VAPID_SUBJECT ?? '',
    REMINDER_URL: process.env.REMINDER_URL ?? '',
    REMIND_TOKEN: process.env.REMIND_TOKEN ?? '',
    DB_PATH: dbPath,
    R2_DIR: r2Dir,
  };
}
