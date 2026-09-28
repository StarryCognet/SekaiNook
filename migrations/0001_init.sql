-- SekaiNook D1 初始化：家庭积分流水 + 每周学习计划
-- 应用方式：wrangler d1 migrations apply sekainook --remote

-- ===== 积分流水表 =====
CREATE TABLE IF NOT EXISTS family_ledger (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL,
  task_name TEXT NOT NULL,
  type TEXT NOT NULL,
  amount INTEGER NOT NULL,
  note TEXT,
  image_url TEXT,
  -- pending 待审批 | approved 已入账 | rejected 已驳回
  status TEXT NOT NULL DEFAULT 'approved',
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_family_ledger_status ON family_ledger(status);
CREATE INDEX IF NOT EXISTS idx_family_ledger_created_at ON family_ledger(created_at);

-- ===== 每周学习计划表 =====
CREATE TABLE IF NOT EXISTS weekly_plans (
  id TEXT PRIMARY KEY,
  subject TEXT NOT NULL,
  task_name TEXT NOT NULL,
  target INTEGER NOT NULL,
  current INTEGER NOT NULL DEFAULT 0,
  week_label TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_weekly_plans_week ON weekly_plans(week_label);
-- 同一周内任务名唯一，保证「初始化本周计划」幂等
CREATE UNIQUE INDEX IF NOT EXISTS idx_weekly_plans_week_task ON weekly_plans(week_label, task_name);
