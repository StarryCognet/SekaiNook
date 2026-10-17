-- 0005: Web Push 订阅端点（每天 21:30 提醒「今天还差几个任务」用）
--
-- 设计取舍：
--   * endpoint 直接当主键：浏览器给的推送端点天生唯一（同一个 Service Worker 重复订阅拿到的是同一个
--     endpoint），所以它同时是 UPSERT 的目标 —— 重复订阅只更新 keys，不会攒出一堆废记录。
--   * 没有账号体系，就用两格身份：audience = 'parent' | 'child'，记下是哪台设备/哪个身份订阅的，
--     发送时按它挑要推给谁（沿用 0003 notifications 的思路）。
--   * p256dh / auth 是浏览器订阅时给的加密参数，缺一不可 —— 发推送时要用它们加密 payload。
--   * ua 只存 User-Agent 片段（接口里截断到 200 字），方便家长在设置页认出「这台是外婆的 iPad」。
--   * 订阅是会过期的（卸载浏览器 / 清数据 / 推送服务回收），发送端拿到 404/410 时按 endpoint 删行即可，
--     所以这张表只增不改结构。
--   * 本迁移幂等，可重复执行。
--
-- 应用方式：
--   本地：npm run db:migrate:local
--   线上：npm run db:migrate:remote（部署新前端前必须先执行）

CREATE TABLE IF NOT EXISTS push_subscriptions (
  endpoint   TEXT PRIMARY KEY,               -- 浏览器给的推送端点，天然唯一
  audience   TEXT NOT NULL DEFAULT 'child',  -- parent | child，记下是哪台设备/哪个身份订阅的
  p256dh     TEXT NOT NULL,
  auth       TEXT NOT NULL,
  ua         TEXT,                           -- User-Agent 片段，方便家长认出是哪台设备
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- 发送时按 audience 取订阅（推给家长还是孩子），索引比全表扫划算，也顺带覆盖按身份数设备
CREATE INDEX IF NOT EXISTS idx_push_subscriptions_audience
  ON push_subscriptions(audience);
