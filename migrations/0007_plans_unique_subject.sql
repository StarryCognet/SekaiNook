-- 0007：weekly_plans 的唯一键补上 subject
--
-- 0001 里建的是 UNIQUE(week_label, task_name)。不同科目下可能出现同名任务
-- （比如语文「阅读」和英语「阅读」），第二条会被唯一索引静默丢掉，
-- 而接口照样回 201 —— 用户看到「保存成功」，刷新后少一条。
--
-- 改成 UNIQUE(week_label, subject, task_name)。旧数据满足旧唯一键，
-- 因此新索引一定能建起来。
--
-- 可重入：DROP INDEX IF EXISTS + CREATE UNIQUE INDEX IF NOT EXISTS。

DROP INDEX IF EXISTS idx_weekly_plans_week_task;

CREATE UNIQUE INDEX IF NOT EXISTS idx_weekly_plans_week_subject_task
  ON weekly_plans (week_label, subject, task_name);
