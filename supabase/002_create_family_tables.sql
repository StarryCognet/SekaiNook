-- SekaiNook 家庭财务与行为管理：建表 SQL
-- 在 Supabase SQL Editor 中执行本文件

-- ===== 积分流水表 =====
create table if not exists family_ledger (
  id uuid primary key default gen_random_uuid(),
  task_id text not null,
  task_name text not null,
  type text not null,
  amount int not null,
  created_at timestamptz default now()
);

-- ===== 每周学习计划表 =====
create table if not exists weekly_plans (
  id uuid primary key default gen_random_uuid(),
  subject text not null,
  task_name text not null,
  target int not null,
  current int default 0,
  week_label text not null
);

-- ===== 开启 RLS，对 anon 开放 select/insert/update =====
alter table family_ledger enable row level security;
alter table weekly_plans enable row level security;

-- family_ledger 策略
drop policy if exists "family_ledger_select" on family_ledger;
create policy "family_ledger_select" on family_ledger
  for select to anon using (true);

drop policy if exists "family_ledger_insert" on family_ledger;
create policy "family_ledger_insert" on family_ledger
  for insert to anon with check (true);

drop policy if exists "family_ledger_update" on family_ledger;
create policy "family_ledger_update" on family_ledger
  for update to anon using (true) with check (true);

-- weekly_plans 策略
drop policy if exists "weekly_plans_select" on weekly_plans;
create policy "weekly_plans_select" on weekly_plans
  for select to anon using (true);

drop policy if exists "weekly_plans_insert" on weekly_plans;
create policy "weekly_plans_insert" on weekly_plans
  for insert to anon with check (true);

drop policy if exists "weekly_plans_update" on weekly_plans;
create policy "weekly_plans_update" on weekly_plans
  for update to anon using (true) with check (true);

-- ===== 初始化本周学习计划（可选，按需执行）=====
-- 说明：以下为当前周（2026-W34）的示例初始化数据。
-- 每周需为新的一周插入对应 week_label 的数据，week_label 格式：ISO年-W周数（如 2026-W34）。
insert into weekly_plans (subject, task_name, target, current, week_label) values
  ('英语', '单词背诵', 50, 0, '2026-W34'),
  ('英语', '小作文', 1, 0, '2026-W34'),
  ('语文', '课文预习', 2, 0, '2026-W34'),
  ('语文', '课外阅读', 3, 0, '2026-W34'),
  ('数学', '口算练习', 5, 0, '2026-W34'),
  ('数学', '错题订正', 10, 0, '2026-W34'),
  ('日常', '9:00前睡觉', 7, 0, '2026-W34'),
  ('日常', '7:00起床', 7, 0, '2026-W34')
on conflict do nothing;