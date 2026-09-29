# SekaiNook · 家庭财务与行为管理

一套专为家庭设计的「行为与积分银行」。通过量化家务（赚钱）、电子产品使用（花钱）、作息与视力（罚款）以及每周学习计划，实现家庭行为的数字化管理。一套代码，多端适配。

## ✨ 功能特性

### 🏡 首页（第 1 个标签，按身份分成两套界面）
打开 App 的第一屏，妹妹和妈妈看到的是完全不同的两套页面（同一台设备只有一个人在用）：
- **女儿版**（配色跟随全局主题）：发光大白字阳光积分、连续天数与勋章进度、今日学习任务一键完成、21 点还没做完任务的提醒条、「我的积分」本周赚了多少花掉多少、妈妈说的最新一句话、8 个常用入口宫格（去打卡 / 背古诗 / 花园 / 妈妈的话 / 本周计划 / 我的账本 / 勋章 / 设置）
- **妈妈版**（同样跟随主题）：实时时钟、待审批数与当前余额两个大数字、「需要我处理」待办（待审批 / 可兑现 / 本周计划落后）点一下直达、本周收入支出净额与打卡次数 + 近 14 天趋势图、女儿今天的流水（可在首页直接兑现清零）、入口宫格（去审批 / 账本 / 计划 / 花园 / 通知 / 导出流水 / 结算兑现 / 设置）
- 「去审批」会直接把账本页切到待审批那一页

### 🔔 通知收件箱
- 妹妹提交打卡、妈妈直接记账、审批通过 / 驳回、重新提交、结算兑现，都会给对方留一条站内消息
- 首页标签挂未读角标（家庭标签挂待审批数），点开 `/home/notifications` 看完整收件箱，支持一键全部已读、点条目跳到对应页面
- 通知只由服务端在事件处写入（没有「创建通知」接口，客户端造不出假消息）；「今天任务没做完」「21 点了」这类待办提醒在首页即时计算，不进收件箱

### 🏠 家庭工作台（积分银行）
- **积分余额**：大数字展示当前总积分（由已审批流水汇总），正数绿色、负数红色
- **任务区**：一键打卡赚钱任务（整理房间、洗碗、按时完成作业、按时睡觉等）与消费/罚款任务（看 iPad、玩手机、视力下降等）
- **打卡弹窗**：拍照/选图上传（浏览器端压缩后传 R2）+ 备注
- **待审批 Tab**：家长审批小孩提交的打卡申请（通过 / 驳回），侧边栏与底部导航红点角标 + 10 秒轮询提醒
- **自定义任务**：自由填写类型（赚钱 / 消费·罚款）、名称、价格，创建专属任务（仅家长可见）
- **历史记录区**：完整积分流水账本，按时间倒序展示，每条附审批状态（已入账 / 待审批 / 已驳回）与备注/图片；状态筛选 + 「加载更多」分页；家长可删除单条记录（连带清理 R2 中的图片）并一键导出 CSV，小孩可撤回待审批的申请
- **结算兑现**：家长可在余额为正时一键「结算兑现（清零余额）」，写入一条现金兑现流水，让积分与现金形成闭环
- **收支趋势**：近 14 天每日净积分柱状图（`echarts/core` 按需引入，切到家庭工作台才会下载）
- **今日任务与作息**：实时时钟 + 作息状态提醒

### 📅 每周学习计划
- 英语、语文、数学、日常四大类学习目标
- 进度实时统计，未达标灰色、达标绿色高亮
- 支持调整目标数量与打卡

### 🌻 阳光花园・学习乐园（儿童工作台）
专为孩子设计的趣味学习空间，完成学习任务获得「阳光积分」。界面与全站其余部分同一套卡片、圆角、描边与阴影，颜色全部取自全局主题 —— 切到「午夜蓝」时花园也跟着变深色，不再是单独一块紫色皮肤：
- **今日任务**：古诗背诵、语文预习、数学预习、课外阅读等，图标 + 完成动画
- **古诗背诵 / 语文预习**：专项学习页面
- **阳光花园**：装饰自己的花园
- **阳光商城**：用阳光积分兑换奖励
- **我的奖励**：勋章墙 + 成就进度
- **学习记录**：学习历史

### 🔐 身份与家长口令
- **双角色**：家长（可审批、可增删记录）/ 小孩（打卡后需家长审批）
- **身份选择门**：新设备首次打开先选身份，不默认进家长模式（避免小孩自审自批）
- **家长口令**：切换为家长需口令，出厂 `1234`，可在设置页改为 4-8 位
- **打卡规则在服务端**：分数、任务名、每天次数上限与可打卡时间段由 `functions/_lib/rules.ts` 唯一维护；`POST /api/ledger` 一律忽略客户端报上来的分数与审批状态，按规则改写（花园类任务即时到账、家庭任务一律 pending 交家长审批），每次打卡自带唯一 id，重试或离线补发只入账一次，越出时间窗或超过每天次数返回 409 并给出「今天已经打过卡啦」「每天最多 N 次」
- **称呼可改、跨设备同步**：视角以自己的角度出发 —— 妈妈的手机上看到的是「女儿」，女儿的手机上看到的是「妈妈」。设置页「称呼设置」里，女儿改妈妈那半（称呼 + 昵称），妈妈改女儿那半；昵称优先，没填昵称才用称呼；存在云端 `settings` 表，换设备打开是同一套名字（站内通知文案也跟着改口）
- **主题与背景**：设置页「外观」里可切换**七套主题** —— 原始（浅色深蓝主色，出厂默认）、樱花粉、森林绿、暖阳橙（四套浅色）、午夜蓝、暗夜红、石墨黑（三套深色，晚上看不刺眼；石墨黑照那份《Mobile App UI》规范做的：近黑底 + 白墨 + 发丝线 + 玻璃胶囊）；每套主题都带完整配色（卡片、描边、阴影、底部毛玻璃导航、提示色块、手机地址栏颜色一起换），切完整站一起变（首页的女儿版 / 妈妈版、账本、学习计划、花园、设置全都跟着换）；顶栏**右上角那颗太阳 / 月亮按钮**可一键在浅色与深色之间来回，回的是你上次各用的那一套（比如白天樱花粉、晚上暗夜红）；主题记在本机（各设备各选），背景图存在云端（各设备一致）。也能选一张照片上传当全局背景图，卡片自动半透明、文字保持清晰；正在使用的背景图不会被「闲置照片清理」误删
- **设置页 `/settings`**：两层结构 —— 外层只列大类入口（外观 / 家庭 / 家长管理，每个入口带一句现状概述，比如「现在是『午夜蓝』主题 · 已设背景图」），点进去在第二层改具体项、顶部「‹ 设置」返回，此时外层的「关于」与版本日志一起让位、只看这一组设置；退回入口列表它们再回来。应用信息与版本日志不分层，版本日志默认收起（只显示最近 3 个版本）可展开全部 / 收起。各层内容：外观（主题、全局背景图）、家庭（切换身份、设置对方称呼）、家长管理（修改家长口令、扫描并清理云端闲置打卡照片），当前 v1.25.0
- **多端导航**：PC 固定侧边栏 + 面包屑（菜单选中项是圆角胶囊），顶栏右侧是「积分小胶囊（点进家庭账本）+ 通知铃铛（未读挂角标）+ 日/月两段式深浅开关」；手机端为一对悬浮毛玻璃胶囊 —— 顶部是「当前页图标 + 页面名」加右侧的铃铛与深浅开关，底部是 Tab 栏（首页 / 家庭 / 计划 / 花园 / 设置，选中项的高光是一块会走的**毛玻璃片**（顶部高光 + 发丝边 + 内外两层落影）：短按换标签时它沿一条真弹簧滑到位（过冲比例恒定 15% ~ 18%，所以跨一格只甩出去十几像素、越短越轻，跨得远才摆得大，时长 0.55 ~ 0.78 秒）；**长按 0.17 秒就能把它「拿起来」** —— 那一项跟着放大、玻璃按手指速度被横向拉长、身后还拖着一道模糊水痕，松手落到哪一项就弹到哪一项；图标转实心、再点当前标签回顶部、切换标签保留各页位置与筛选）；**手机端往下滑看内容时顶栏向上、Tab 栏向下各自滑走让出屏幕，往上滑或回到顶部原路滑回来（0.3 秒过渡）**；七套主题共用同一套导航结构，颜色全走主题变量（换主题时导航栏一起换）
- **PWA**：可「添加到主屏幕」当 App 用（manifest + Service Worker 缓存静态资源；接口数据仍然实时请求、永不缓存）

## 🛠 技术栈

| 类别 | 技术 |
|------|------|
| 前端框架 | React 18 + TypeScript + Vite 5 |
| UI 组件库 | antd 6（PC 端与移动端同一套；不使用 antd-mobile） |
| 状态管理 | zustand 5 |
| 路由 | react-router-dom 6 |
| 图表 | echarts：家庭工作台「近 14 天积分趋势」图（必须 `echarts/core` 按需引入 BarChart + GridComponent + TooltipComponent + CanvasRenderer；禁止整包 import，禁止 echarts-for-react——它依赖未安装的 tslib） |
| 日期 | dayjs（ISO 周计算、antd 中文语言包） |
| 图标 | @ant-design/icons |
| 后端 | Cloudflare Pages Functions（文件即路由，`functions/api/`） |
| 数据库 | Cloudflare D1（SQLite，绑定名 `DB`，database `sekainook`） |
| 对象存储 | Cloudflare R2（绑定名 `STARRYMIKU_BUCKET`，bucket `starrymiku`） |
| 部署 | Cloudflare Pages（`pages_build_output_dir=./dist`，`compatibility_date=2025-09-01`） |

> 后端已于提交 `4e6347c` 从 Supabase 迁移到 Cloudflare Pages Functions + D1 + R2，仓库中不再有任何 Supabase 依赖、配置或 SQL。
>
> 移动端不引入 antd-mobile：PC 端与移动端统一使用 antd（移动端细节由各页 CSS Module 适配），antd-mobile 已从依赖中移除。

## 🚀 快速开始

### 环境要求
- Node.js 18+
- npm 9+
- wrangler（devDependency，随 `npm install` 安装）

### 安装与运行

```bash
# 安装依赖
npm install

# 首次：把 migrations 应用到本地 D1
npm run db:migrate:local

# 终端 1：启动后端（Pages Functions + 本地 D1/R2），端口 8788
npm run dev:api

# 终端 2：启动前端，端口 5173（/api 已代理到 http://127.0.0.1:8788）
npm run dev

# 生产构建：先生成绑定类型，再类型检查，最后打包
npm run build

# 预览构建产物
npm run preview

# 部署（build + wrangler pages deploy）
npm run deploy

# 线上数据库迁移
npm run db:migrate:remote
```

### 环境变量与绑定

前端**不需要任何环境变量**：

- 本地与构建期：D1 / R2 绑定全部来自 `wrangler.jsonc`（`db:migrate:*` 也用同一份配置）
- 线上：在 Cloudflare Dashboard 的 Pages 项目 Settings → Bindings 里配置同名绑定

历史上用于 Supabase 的 `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` 已随迁移删除（`.env` 仅保留说明性注释，不再是运行前提）。

### 数据分层

- **D1 云端（跨设备共享）**：`family_ledger`（积分流水）、`weekly_plans`（每周学习计划）、`notifications`（站内通知收件箱）、`settings`（家庭称呼 + 全局背景图等跨设备设置）；图片存 R2
- **localStorage 本地（各设备独立）**：当前身份角色、家长口令、阳光花园数据、导航与筛选等界面状态（`sessionStorage`）

### 装到手机桌面（PWA）

线上部署后（`npm run deploy`）用手机浏览器打开站点：

- **安卓 Chrome**：菜单 → 「添加到主屏幕」，之后从桌面图标启动即无地址栏全屏
- **iPhone Safari**：分享 → 「添加到主屏幕」
- Service Worker 只缓存静态资源（JS/CSS/图标），`/api/*` 永不缓存：断网能打开界面，数据仍需网络；`npm run dev` 不注册 Service Worker，改代码不会看到旧缓存

## 📁 目录结构

```
functions/api/            # 后端接口（文件路径即 URL 路径）
├── ledger/index.ts       #   GET/POST     /api/ledger（支持 ?status= 过滤）
├── ledger/[id].ts        #   PATCH/DELETE /api/ledger/:id
├── plans/index.ts        #   GET/POST     /api/plans（按 week_label 幂等初始化）
├── plans/[id].ts         #   PATCH        /api/plans/:id
├── upload.ts             #   POST         /api/upload（图片入 R2，5MB 上限）
├── images/[[key]].ts     #   GET          /api/images/:key（[[key]] 匹配多段）
├── notifications/index.ts    # GET   /api/notifications（按 audience 取信箱 + 未读数）
├── notifications/[id].ts     # PATCH /api/notifications/:id（标记已读 / 未读）
├── notifications/read-all.ts # POST  /api/notifications/read-all（整格信箱一键已读）
├── settings/index.ts     #   GET/PATCH    /api/settings（家庭称呼 + 全局背景图，跨设备同步）
└── maintenance/orphans.ts #  GET/POST     /api/maintenance/orphans（闲置照片扫描 / 清理）
functions/_lib/           # 后端共用模块（不下划线开头会被当成路由，所以放 _lib）
migrations/               # D1 建表 SQL（编号递增，必须幂等；0002 给流水加 member 列，0003 建通知表，0004 建 settings 键值表）
public/_routes.json       # 声明 Functions 只接管 /api/*
public/_redirects         # SPA 路由回退 /* → /index.html 200
wrangler.jsonc            # D1 / R2 绑定与 Pages 构建配置

src/
├── api/            # 数据访问层（http.ts 统一 REST 客户端 + familyLedger/familyTasks/upload/notifications）
├── components/     # 通用组件（加载/空/错误态、身份选择门、打卡弹窗、花园图标）
├── config/         # 业务规则唯一数据源（任务、学习计划、花园配置、版本日志）
├── layouts/        # 主布局（PC 侧边栏 + 移动端底部导航）、花园布局
├── store/          # zustand 全局状态（积分流水/审批/身份/口令、花园）
├── theme/          # 设计令牌（颜色/间距/圆角）
├── types/          # TypeScript 类型定义
├── utils/          # 工具函数（设备判断、ISO 周计算、图片压缩）
└── views/
    ├── home/       # 首页（妹妹版 / 妈妈版）与通知收件箱
    ├── family/     # 家庭工作台、每周学习计划
    ├── garden/     # 阳光花园儿童工作台
    └── settings/   # 设置（身份/口令/主题与背景/版本日志）
```

## 🧭 路由

| 路径 | 页面 |
|------|------|
| `/` | 自动跳转 `/home` |
| `/home` | 首页（按身份显示妹妹版 / 妈妈版） |
| `/home/notifications` | 通知收件箱 |
| `/family` | 家庭工作台（积分银行 / 账本） |
| `/family/plan` | 每周学习计划 |
| `/garden` | 阳光花园・学习乐园 |
| `/settings` | 设置（身份切换、家长口令、主题与全局背景图、版本日志） |

未选择身份时会先显示身份选择门；未知路径回退到 `/home`。

## 🔌 后端接口

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/ledger` | 流水列表（倒序，支持 `?status=pending\|approved\|rejected`） |
| POST | `/api/ledger` | 新增流水（小孩打卡传 `status=pending`，默认 `approved`） |
| PATCH | `/api/ledger/:id` | 更新审批状态（审批通过 / 驳回 / 重新提交） |
| DELETE | `/api/ledger/:id` | 删除流水，并清理关联的 R2 图片 |
| GET | `/api/plans?week=<label>` | 查询某周计划 |
| POST | `/api/plans` | 幂等初始化某周计划 |
| PATCH | `/api/plans/:id` | 更新单项进度 |
| POST | `/api/upload` | 上传图片到 R2（jpeg/png/webp/gif，≤5MB） |
| GET | `/api/images/:key` | 读取 R2 图片（匿名，供 `<img>` 直接用） |
| GET | `/api/maintenance/orphans` | 扫描 R2 中未被流水引用的闲置打卡照片（只读，返回 `{ total, referenced, orphans, keys }`） |
| POST | `/api/maintenance/orphans` | 删除闲置打卡照片，需请求体 `{"confirm":true}` |
| GET | `/api/notifications?audience=parent\|child` | 取某格信箱的通知（倒序，`limit` 缺省 50 / 上限 200），返回 `{ items, unreadCount, ready }`（`ready=false` = 通知表还没迁移） |
| PATCH | `/api/notifications/:id` | 标记单条已读 / 未读（请求体 `{"status":"read"\|"unread"}`） |
| POST | `/api/notifications/read-all` | 整格信箱一键已读（请求体 `{"audience":"parent"\|"child"}`） |
| GET | `/api/settings` | 读取家庭称呼与全局背景图（`{ names: { momCall, momNickname, kidCall, kidNickname }, background, ready }`，`ready=false` = settings 表还没迁移） |
| PATCH | `/api/settings` | 部分更新称呼或背景图（只传要改的字段，称呼最多 12 字，留空回默认「妈妈 / 女儿」；`background` 只能是本站 `/api/images/` 地址，传空串 = 移除背景图） |

接口**刻意不加鉴权**：本项目是家庭内部工具，权限靠前端身份与家长口令约束（见下方开发规则）。

## 📜 业务规则

### 赚钱任务（正数）
| 任务 | 积分 |
|------|------|
| 整理房间 | +10 |
| 洗碗 | +5 |
| 洗衣服 | +15 |
| 倒垃圾 | +5 |
| 按时完成作业 | +20 |
| 课外阅读 30 分钟 | +10 |
| 按时睡觉 | +10 |

### 消费 / 罚款（负数）
| 任务 | 积分 |
|------|------|
| 看 iPad 30 分钟 | -10 |
| 玩手机 30 分钟 | -10 |
| 视力下降 1 度 | -100 |
| 未按时作息（晚于 21:00） | -20 |
| 作业未完成 | -50 |

### 每周学习计划
英语：单词背诵 50、小作文 1；语文：课文预习 2、课外阅读 3；数学：口算练习 5、错题订正 10；日常：9:00 前睡觉 7、7:00 起床 7。

以上规则的唯一数据源是 `src/config/familyRules.ts`，接口与数据库只存结果，不重复定义规则。

## 🧱 开发规则（铁律）

完整规范见 `.trae/rules/project_rules.md`（新增接口、建表、前端调用前必读）。核心约束：

1. **代理必须用 `127.0.0.1`**：Node 可能把 `localhost` 解析到 IPv6 `::1`，而 workerd 只监听 IPv4（表现为 500/502）
2. **`build` 脚本必须先跑 `wrangler types`**：`worker-configuration.d.ts` 被 gitignore，CI 上不存在，不生成会导致 `tsc` 找不到 `Env` / `PagesFunction` 类型
3. **`public/_routes.json` 必须保持 `include: ["/api/*"]`**：否则 `_redirects` 的 SPA 兜底会把接口请求吞成 HTML
4. **不引入鉴权中间件 / 共享口令校验**：家庭内部简单 CRUD，接口默认公开，鉴权只在前端做
5. **`/api/images/*` 保持匿名**：`<img>` 无法携带请求头
6. **改动绑定要同步三处**：`wrangler.jsonc`、Cloudflare Dashboard 的 Pages 绑定、函数内的 `interface Env`
7. **绑定名固定**：D1 = `DB`，R2 = `STARRYMIKU_BUCKET`，不要改名
8. **前端所有请求走 `src/api/http.ts`**，业务代码禁止裸写 `fetch`（`src/api/upload.ts` 是唯一例外：请求体是二进制图片）
9. **组件禁止直接访问 D1/R2**，必须经 `src/api/` 封装
10. **禁止引入依赖 `tslib` 的库（如 `echarts-for-react`）**：项目未安装 `tslib`，打包会留下未解析的 `import ... from "tslib"`，对应 chunk 在浏览器里直接加载失败；图表请用 `echarts/core` 自建容器组件（见 `src/components/BalanceTrend.tsx`）

## 📄 License

MIT
