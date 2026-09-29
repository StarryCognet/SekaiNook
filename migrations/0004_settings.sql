-- 0004：应用级共享设置（键值对）
--
-- 目前只用来存家庭称呼：女儿怎么叫妈妈、妈妈怎么叫女儿。
-- 放云端而不是 localStorage，是因为两个人的手机要看到同一套称呼。
-- 通用键值表也方便以后加别的跨设备设置，不用再建表。
--
-- 幂等：重复执行不报错。

CREATE TABLE IF NOT EXISTS settings (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
