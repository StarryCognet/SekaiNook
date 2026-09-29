-- 0003: 通知收件箱（首页的「通知」来源）
--
-- 设计取舍：
--   * 没有账号体系，就用两格信箱：audience = 'parent' | 'child'。
--     服务端写好收件人，前端按当前身份只读自己那一格。
--   * 通知只由服务端在事件发生处写入（记账 / 审批 / 结算），不开放创建接口，
--     避免客户端乱造数据。
--   * dedupe_key 有唯一索引：同一个事件被重试或重复提交时只保留第一条，
--     不会把收件箱刷屏。dedupe_key 为 NULL 时 SQLite 不参与唯一性判断，
--     所以「每次都要留一条」的通知可以不传。
--   * 本迁移幂等，可重复执行。
--
-- 应用方式：
--   本地：npm run db:migrate:local
--   线上：npm run db:migrate:remote（部署新前端前必须先执行）

CREATE TABLE IF NOT EXISTS notifications (
  id TEXT PRIMARY KEY,
  audience TEXT NOT NULL,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT,
  link TEXT,
  dedupe_key TEXT,
  status TEXT NOT NULL DEFAULT 'unread',
  created_at TEXT NOT NULL,
  read_at TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_notifications_dedupe ON notifications(dedupe_key);

CREATE INDEX IF NOT EXISTS idx_notifications_audience_created
  ON notifications(audience, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_audience_status
  ON notifications(audience, status);
