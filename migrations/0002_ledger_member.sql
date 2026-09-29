-- 0002: 流水支持家庭成员（多孩子场景，可选字段）
--
-- 设计取舍：
--   * member 为空 = 未指定成员。单孩子家庭不配置成员，界面上完全不出现这个概念，
--     行为与迁移前完全一致（向后兼容）。
--   * 代码对「尚未执行本迁移」的库也保持兼容：GET 用 SELECT *（列不存在就读不到），
--     POST 只在请求里真的带了 member 时才写这一列。
--
-- 应用方式：
--   本地：npm run db:migrate:local
--   线上：npm run db:migrate:remote（部署新前端前必须先执行）

ALTER TABLE family_ledger ADD COLUMN member TEXT;

CREATE INDEX IF NOT EXISTS idx_family_ledger_member ON family_ledger(member);
