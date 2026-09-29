SekaiNook 是一套专为家庭设计的“行为与积分银行SaaS”。通过量化家务（赚钱）、电子产品使用（花钱）、作息与视力（罚款）及每周学习计划，实现家庭行为的数字化管理。一套代码，多端适配。
工程文件夹/包名 = SekaiNook（不得改）；界面品牌名 = SekaiNook。
技术栈（钉死，不得替换）
React 18 + TypeScript + Vite 5
antd 6（PC端大屏与仪表盘使用）
zustand 5（全局状态管理，如当前积分余额）
react-router-dom 6（路由管理，禁止使用 v7）
echarts（家庭工作台「近 14 天积分趋势」图；必须用 echarts/core 按需引入 BarChart + GridComponent + TooltipComponent + CanvasRenderer，禁止整包 import echarts 拖累首屏；禁止引入 echarts-for-react —— 它依赖的 tslib 未安装，会把未解析的 `import ... from "tslib"` 打进产物，导致整块 chunk 在浏览器里加载失败）
@ant-design/icons（图标库）
dayjs（ISO 周计算、antd 中文语言包，已声明为直接依赖）
后端：Cloudflare Pages Functions（文件即路由，functions/api/）+ D1（SQLite）+ R2（对象存储）。绑定名固定：D1 = DB，R2 = STARRYMIKU_BUCKET。
自提交 4e6347c 起已从 Supabase 迁移，仓库内不得再引入 @supabase/supabase-js、supabase/ 目录或任何 Supabase 配置；前端经 src/api/ 调用 /api/*，不直连数据库，因此不存在 RLS / anon key 概念。
禁止引入：Tailwind、Redux、vitest、testing-library
一套代码多端形态（路由分流）
未选择身份（新设备首次打开）→ 先过身份选择门（家长需口令），不默认进家长模式
手机APP/手机浏览器 / → 自动跳 /family（移动端工作台，底部导航：家庭/计划/花园/设置）
电脑浏览器 / → 自动跳 /family（PC端仪表盘，固定侧边栏）
学习计划 /family/plan → 每周学习进度表
阳光花园 /garden → 儿童学习工作台
设置 /settings → 身份切换（家长/小孩）、家长口令修改、应用版本与版本日志
目录结构
src/
├── api/ http.ts（唯一 REST 出口）/ familyLedger.ts / familyTasks.ts / upload.ts
├── config/ familyRules.ts（赚钱/花钱/学习计划规则唯一数据源）/ garden.ts / changelog.ts（版本日志）
├── components/ StateViews.tsx（全局加载/空/错误态）/ RoleGate.tsx（身份选择门）/ garden/
├── layouts/ MainLayout.tsx（PC侧边栏+移动端底部Tab）/ GardenLayout.tsx
├── store/ useFamilyStore.ts（流水/审批/身份/口令）/ useGardenStore.ts
├── theme/ global.css / tokens.ts / gardenTokens.ts（设计令牌）
├── types/ family.ts / garden.ts（类型定义）
├── utils/ device.ts / week.ts（设备判断/ISO周计算）/ image.ts（上传前压缩）
└── views/
    ├── family/ FamilyDashboard.tsx / WeeklyPlan.tsx
    ├── garden/ 学习总览/今日任务/古诗背诵/语文预习/花园/商城/奖励/记录
    └── settings/ SettingsPage.tsx
后端目录：functions/api/（文件路径即路由）
functions/api/ledger/index.ts → GET/POST /api/ledger
functions/api/ledger/[id].ts → PATCH/DELETE /api/ledger/:id
functions/api/plans/index.ts → GET/POST /api/plans
functions/api/plans/[id].ts → PATCH /api/plans/:id
functions/api/upload.ts → POST /api/upload
functions/api/images/[[key]].ts → GET /api/images/:key
铁律
只用 antd（PC 端与移动端同一套）；不引入 antd-mobile；同一 .tsx 禁止混用两套组件库。
所有颜色/间距/圆角/阴影必须从 theme/tokens.ts 读取，禁止硬编码 hex/px 值。
前端所有请求必须走 src/api/http.ts（统一 JSON 序列化与 ApiError 归一化），业务代码禁止裸写 fetch；唯一例外是 src/api/upload.ts（请求体是二进制图片）。组件禁止直接访问 D1/R2，必须经 src/api/ 封装。
任务名/积分值/学习目标全部从 config/familyRules.ts 读，禁止硬编码。
禁止 any；props 必须 interface；禁止 class 组件。
数字展示元素必须加 className="num"（Oswald字体）。
所有可见文字默认使用中文。
移动端优先：先保证 375px 宽度下交互正常。
接口默认不鉴权（不引入鉴权中间件/共享口令校验）：家庭内部工具，权限由前端身份 + 家长口令承担，后端接口保持公开。
/api/images/* 必须保持匿名（<img> 标签无法携带请求头）。
vite 代理必须写 http://127.0.0.1:8788，不能写 localhost：Node 可能解析到 IPv6 ::1，而 workerd 只监听 IPv4（表现为 500/502）。
build 脚本必须先跑 wrangler types：worker-configuration.d.ts 被 gitignore，CI 上不存在，不生成会导致 tsc 找不到 Env / PagesFunction 类型。
public/_routes.json 必须保持 include: ["/api/*"]：否则 public/_redirects 的 SPA 兜底会把接口请求吞成 HTML。
改动绑定必须同步三处：wrangler.jsonc、Cloudflare Dashboard 的 Pages 绑定、函数内的 interface Env；绑定名固定 DB / STARRYMIKU_BUCKET，不得改名。
后端细节（新建表/新增接口）的完整规范见 .trae/rules/project_rules.md，本文件不重复展开。
命名规范
组件 PascalCase；hooks 用 use 开头；api 文件 camelCase；表名 snake_case；任务 id 用 snake_case 英文；D1 表列名与 src/types 字段保持 snake_case 一致。
week_label 格式规约
格式 = ISO年 + "-W" + 两位周数，例：2026-W34。
前端用 src/utils/week.ts 的 getIsoWeekLabel() 生成（dayjs isoWeek 插件）。
后端不生成周标签：D1/SQLite 无 to_char()，week_label 一律由前端生成后作为参数/字段传入（GET /api/plans?week=<label>、POST /api/plans 的 week_label）。
数据库表结构（D1，见 migrations/0001_init.sql，全部语句幂等）
family_ledger（积分流水表）：
id TEXT 主键；task_id TEXT；task_name TEXT；type TEXT ('earning'|'spending')；amount INTEGER；note TEXT；image_url TEXT（R2 图片地址 /api/images/<key>）；status TEXT（'pending' 待审批 | 'approved' 已入账 | 'rejected' 已驳回，默认 approved）；created_at TEXT（ISO 字符串）。索引：status、created_at。
weekly_plans（学习计划表）：
id TEXT 主键；subject TEXT；task_name TEXT；target INTEGER；current INTEGER（默认 0）；week_label TEXT；created_at TEXT。索引：week_label；唯一索引 (week_label, task_name) 保证「初始化本周计划」幂等（INSERT OR IGNORE）。
不用 RLS：D1 只能经 Pages Functions 访问，前端不直连数据库。
核心业务规则（config/familyRules.ts 必须严格遵守）
1. 赚钱区（earning，正数）
clean_room: 整理房间, +10
wash_dishes: 洗碗, +5
do_laundry: 洗衣服, +15
take_out_trash: 倒垃圾, +5
finish_homework: 按时完成作业, +20
read_book: 课外阅读30分钟, +10
sleep_on_time: 按时睡觉, +10（仅 19:00-21:30 可打卡）
2. 花钱区（spending，负数）
ipad_time: 看iPad 30分钟, -10
phone_time: 玩手机 30分钟, -10
3. 罚款区（spending，负数）
eye_penalty: 视力下降1度, -100 (备注: 保护眼睛)
sleep_penalty: 未按时作息(晚于21:00), -20
homework_incomplete: 作业未完成, -50
单项任务可配 dailyLimit（每日次数上限）与 window（可打卡时段），由前端按规则拦截。
4. 每周学习计划（weekly_plans）
英语: 单词背诵(50个/周)、小作文(1篇/周)
语文: 课文预习(2课/周)、课外阅读(3小时/周)
数学: 口算练习(5页/周)、错题订正(10道/周)
日常: 9:00前睡觉(7天/周)、7:00起床(7天/周)
交互与视觉规约
积分银行：余额大数字显示（由已审批流水汇总），正数绿色，负数红色。
任务按钮：赚钱任务使用 success 色，花钱/罚款任务使用 danger 色。
学习进度：未达标灰色，达标绿色高亮。
状态完整性：所有数据加载必须有 PageLoading，无数据有 EmptyState，报错有 ErrorState。
页面过渡：路由切换必须有 fadeSlideIn 动画。
打卡拍照：前端先用 src/utils/image.ts 压缩（长边上限 1600px、JPEG 质量 0.8）再传 R2；后端硬上限 5MB，仅接受 jpeg/png/webp/gif，越界返回 415/413 并把文案透给用户。
审批流（v1.9.0 起）：小孩打卡提交 status=pending，家长审批通过后才计入余额，驳回后小孩可重新提交；家长端待审批 Tab + 红点角标（10 秒轮询）。
身份与口令：家长/小孩双身份存 localStorage；切换为家长需家长口令（出厂 1234，可在设置页改为 4-8 位）。
MVP 范围与二期清单（红线：本阶段禁止实现二期内容）
本阶段只做：积分流水账本、任务打卡（含拍照/备注）、每周学习计划表、PC/移动端响应式布局。
已提前落地（v1.8.0 / v1.9.0 / v1.10.0，视为既有能力，不再算二期）：打卡拍照上传、家长/小孩双身份与家长审批流、设置页与版本日志、历史记录家长删除（连带清理 R2 图片）。
二期（禁止本阶段做）：
奖状兑换商城（家庭积分换礼物）
历史月度报表与趋势分析
