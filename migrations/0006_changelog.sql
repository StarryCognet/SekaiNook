-- 0006: 版本日志上云（设置页「关于」里那份 changelog）
--
-- 设计取舍：
--   * 为什么要从代码常量搬到 D1：网页版（本仓库）和 Flutter 版（SekaiNook-App）是两个仓库、
--     各自打包，版本日志以前各存一份，改一处另一处不跟着变，用户吐槽「一个网页版一个 Flutter 的
--     日志不好同步」。现在两端都读这张表，谁也不必等对方发版。
--   * version 当主键：一个版本只该有一条，重复同步天然是「覆盖」而不是攒出一堆重复行。
--   * changes 存 JSON 数组字符串：D1 是 SQLite，没有数组类型；一条日志也就几条改动，
--     解析成本可以忽略（读取端 functions/_lib/changelog.ts 负责解析与坏行兜底）。
--   * sort_order 记「代码数组里的下标」（0 = 最新），不靠 version / date 排序：
--     版本号是字符串，'1.9.0' 会排到 '1.10.0' 后面；date 也可能同一天里连着写好几条。
--     顺序的唯一真源是 src/config/changelog.ts 的数组，同步时把下标一起写进来。
--   * 代码里那份 CHANGELOG 继续保留，身份变成「播种数据 + 接口不可用时的兜底」：
--     表没迁移 / 请求失败时两端都退回自己 bundle 里那一份，页面不会开天窗。
--   * 本迁移**只建表**，内容由 `npm run changelog:sync` 写入
--     （不把几十条日志抄进 .sql：那就等于又存了一份，正是这次要消掉的问题）。
--   * 本迁移幂等，可重复执行。
--
-- 应用方式：
--   本地：npm run db:migrate:local
--   线上：npm run db:migrate:remote（部署新前端前必须先执行）
--   播种 / 追加版本后同步内容：npm run changelog:sync（默认线上；加 --local 同步本地库）
--   详细说明见 docs/版本日志云端化.md

CREATE TABLE IF NOT EXISTS changelog (
  version    TEXT PRIMARY KEY,   -- 版本号，例如 '1.31.0'
  date       TEXT NOT NULL,      -- 展示用的时间串，例如 '2026-10-17 22:40:00'
  title      TEXT NOT NULL,      -- 这一版的一句话主题
  changes    TEXT NOT NULL,      -- 改动条目，JSON 数组字符串
  sort_order INTEGER NOT NULL,   -- 代码数组里的下标：0 = 最新
  updated_at TEXT NOT NULL
);

-- 读取端永远按 sort_order 升序取，索引顺带覆盖「表里到底有几条」
CREATE INDEX IF NOT EXISTS idx_changelog_sort_order
  ON changelog(sort_order);
