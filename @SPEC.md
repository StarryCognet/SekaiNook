SekaiNook 是一套专为家庭设计的“行为与积分银行SaaS”。通过量化家务（赚钱）、电子产品使用（花钱）、作息与视力（罚款）及每周学习计划，实现家庭行为的数字化管理。一套代码，多端适配。
工程文件夹/包名 = SekaiNook（不得改）；界面品牌名 = SekaiNook。
技术栈（钉死，不得替换）
React + TypeScript + Vite
antd 6（PC端大屏与仪表盘使用）
antd-mobile 5（移动端使用）
zustand 5（全局状态管理，如当前积分余额）
@supabase/supabase-js 2（后端数据库与鉴权）
react-router-dom 6（路由管理，禁止使用 v7）
echarts + echarts-for-react（积分趋势图表）
@ant-design/icons（图标库）
禁止引入：Tailwind、Redux、vitest、testing-library
一套代码多端形态（路由分流）
手机APP/手机浏览器 / → 自动跳 /family（移动端工作台）
电脑浏览器 / → 自动跳 /family（PC端仪表盘）
学习计划 /family/plan → 每周学习进度表
目录结构
src/
├── api/ supabaseClient.ts / familyLedger.ts / familyTasks.ts
├── config/ familyRules.ts（赚钱/花钱/学习计划规则唯一数据源）
├── components/ StateViews.tsx（全局加载/空/错误态）
├── layouts/ MainLayout.tsx（PC侧边栏+顶栏布局）
├── theme/ global.css / tokens.ts（设计令牌）
├── types/ family.ts（类型定义）
├── utils/ device.ts / week.ts（设备判断/ISO周计算）
└── views/
└── family/ FamilyDashboard.tsx / WeeklyPlan.tsx
铁律
PC端只用 antd；移动端只用 antd-mobile；同一 .tsx 禁止混用。
所有颜色/间距/圆角/阴影必须从 theme/tokens.ts 读取，禁止硬编码 hex/px 值。
组件禁止直接写 Supabase 调用，必须经 src/api/ 封装。
任务名/积分值/学习目标全部从 config/familyRules.ts 读，禁止硬编码。
禁止 any；props 必须 interface；禁止 class 组件。
数字展示元素必须加 className="num"（Oswald字体）。
所有可见文字默认使用中文。
移动端优先：先保证 375px 宽度下交互正常。
命名规范
组件 PascalCase；hooks 用 use 开头；api 文件 camelCase；表名 snake_case；任务 id 用 snake_case 英文。
week_label 格式规约
格式 = ISO年 + "-W" + 两位周数，例：2026-W34。
前端用 src/utils/week.ts 的 getIsoWeekLabel() 生成；后端 SQL 用 to_char(now(),'IYYY-"W"IW') 生成。
数据库表结构
family_ledger（积分流水表）：
id uuid 主键；task_id text；task_name text；type text ('earning'|'spending')；amount int；created_at timestamptz。
weekly_plans（学习计划表）：
id uuid 主键；subject text；task_name text；target int；current int；week_label text。
RLS 允许 anon 的 select/insert/update。
核心业务规则（config/familyRules.ts 必须严格遵守）
1. 赚钱区（earning，正数）
clean_room: 整理房间, +10
wash_dishes: 洗碗, +5
do_laundry: 洗衣服, +15
take_out_trash: 倒垃圾, +5
finish_homework: 按时完成作业, +20
read_book: 课外阅读30分钟, +10
2. 花钱区（spending，负数）
ipad_time: 看iPad 30分钟, -10
phone_time: 玩手机 30分钟, -10
3. 罚款区（spending，负数）
eye_penalty: 视力下降1度, -100 (备注: 保护眼睛)
sleep_penalty: 未按时作息(晚于21:00), -20
homework_incomplete: 作业未完成, -50
4. 每周学习计划（weekly_plans）
英语: 单词背诵(50个/周)、小作文(1篇/周)
语文: 课文预习(2课/周)、课外阅读(3小时/周)
数学: 口算练习(5页/周)、错题订正(10道/周)
日常: 9:00前睡觉(7天/周)、7:00起床(7天/周)
交互与视觉规约
积分银行：余额大数字显示，正数绿色，负数红色。
任务按钮：赚钱任务使用 success 色，花钱/罚款任务使用 danger 色。
学习进度：未达标灰色，达标绿色高亮。
状态完整性：所有数据加载必须有 PageLoading，无数据有 EmptyState，报错有 ErrorState。
页面过渡：路由切换必须有 fadeSlideIn 动画。
MVP 范围与二期清单（红线：本阶段禁止实现二期内容）
本阶段只做：积分流水账本、任务打卡、每周学习计划表、PC/移动端响应式布局。
二期（禁止本阶段做）：
奖状兑换商城（积分换礼物）
父母审批流（大额消费需父母授权）
历史月度报表与趋势分析