# SekaiNook 晚间任务提醒 Worker

每天 **21:30（北京时间）** 算一次「今天完成了几个任务」，没做够 5 个就给手机推一条通知：

> **今天还差 5 个任务**
> 已完成 0/5 —— 22:00 前做完，不然扣 10 分。
> 睡觉卡也别忘了：晚于 22:00 打卡要扣 20 分。

线上状态：已部署为 `sekainook-reminder`，cron `30 13 * * *`（21:30 北京），默认通道 **webpush** ——
孩子在 Android Chrome 打开网站、妈妈在 iPhone 把网站加到主屏幕，各自点一次「设置 → 手机提醒 → 开启提醒」即可，
两边都不用装 App。

## 为什么是一个独立 Worker（而不是写在 `functions/` 里）

**Cloudflare Pages 不支持 cron triggers。** `functions/` 只能响应请求，没法「到点自己跑一次」。
所以提醒这部分只能在 Pages 之外起一个带 `[triggers].crons` 的 Worker，读**同一个 D1**
（`database_id` 与 Pages 项目一致）——前端和 Pages Functions 一行都不用改。

## 口径：直接复用 Pages 的那份规则，不重写 SQL

`src/reminder.ts` 里 `import { countDayCompletions, beijingDayBoundsOf, ... } from '../../../functions/_lib/rules'`。

这是刻意的：提醒说「还差 2 个」而日结算算成「还差 3 个」是最难受的 bug，两份口径只要分开写就迟早会漂。
所以「今日完成数」的判定（东八区当日、`status IS NULL 或 approved`（**待审批也算**）、
`type='earning' && amount>0`、排除开户礼金与两种罚款、**按 task_id 去重**）只有 `functions/_lib/rules.ts`
一份实现，这个 Worker 只是调用它。打包时 esbuild 会把那份规则打进来（dry-run 已验证）。

顺带一提：**不要用首页那个「今日进度」**（`src/utils/taskRules.ts` / `lib/core/task_rules.dart`）——
它按设备本地时区分「今天」，分母是「有日限的任务数」，和罚款规则不是一个口径。

## 推送通道：四条，默认 Web Push

`src/channels.ts` 的 `sendPush()` 是唯一出口，`reminder.ts` 不关心走哪条。选择顺序：

**显式 `PUSH_CHANNEL`（`ntfy` / `bark` / `webhook` / `webpush`）> 配了 `BARK_KEY` 走 bark > 配了 `PUSH_WEBHOOK_URL` 走 webhook > VAPID 公私钥齐了走 webpush > 否则 ntfy。**

| 通道 | 适合 | 你要准备的 | 备注 |
| --- | --- | --- | --- |
| `webpush` | **孩子 Android 浏览器 + 妈妈 iPhone 主屏 PWA**，两边都不用装 App | VAPID 密钥对（一次生成，公钥写 vars、私钥做 secret） | 本项目线上默认走这条。iOS 必须先把网站「添加到主屏幕」才收得到（iOS 16.4+） |
| `ntfy` | 想彻底绕开浏览器权限、能接受装个 App | 一个随机主题名（= 密码） | ⚠️ **见下方实测**：ntfy.sh 免费版对 Cloudflare Worker 会 429，自建或付费才稳 |
| `bark` | 孩子用 **iPhone / iPad** 且不想加主屏 | Bark App 里那串 device key | 国内 iOS 最省事，两分钟搞定 |
| `webhook` | 自己有中转（自建服务、IFTTT、群机器人网关…） | 一个接收 URL | payload 固定为 `{title,message,priority,tags,click}`；钉钉/飞书/企业微信的机器人格式不同，需要你自己加一层转换 |

### Web Push 这条通道怎么运作

- 浏览器侧：`public/sw.js` 里 `push` 事件 → `showNotification`，点通知开 `click` 里的地址；订阅由
  `src/utils/push.ts` 用 `GET /api/push/key` 拿到的 VAPID 公钥建立，`POST /api/push/subscribe` 落库。
- 订阅存在 D1 的 `push_subscriptions`（迁移 `0005_push_subscriptions.sql`），**Pages 与 Worker 必须绑同一个
  `database_id`**（见 `wrangler.jsonc`）。
- Worker 侧：`src/webpush.ts` 用 `@block65/webcrypto-web-push` 做 RFC 8291（aes128gcm）+ VAPID JWT 加密，
  逐台 `fetch(endpoint)`；返回 404 / 410 说明这台设备已经废了（卸载了 PWA、清了站点数据），顺手删掉订阅。
- 单台超时 15 秒当失败处理，不会让一次 cron 被一台设备拖死。

### ⚠️ 实测：ntfy.sh 免费版从 Worker 发会被限流

部署后真发一条，返回：

```json
{"code":42908,"http":429,"error":"limit reached: daily message quota reached; increase your limits with a paid plan, see https://ntfy.sh","link":"https://ntfy.sh/docs/publish/#limitations"}
```

同一时刻从家用宽带直连 ntfy.sh 发**同样内容**是 200。原因是 **ntfy.sh 免费额度按出口 IP 算，
而 Cloudflare Worker 的出口 IP 是全体 Cloudflare 客户共用的** —— 所以这条通道在生产上不可靠。要稳定就：

- 用 `bark`（iOS）或 `webhook`（自己的中转）；
- 或者 `NTFY_SERVER` 指向**自建 ntfy**（`https://ntfy.你的域名`，自建实例没有这个公共配额）；
- 或者 ntfy 付费计划 / 带账号令牌（`NTFY_TOKEN`，Worker 会带 `Authorization: Bearer`）。

## 部署

### A. 走 Web Push（本项目线上就是这么配的）

VAPID 密钥对只需生成一次（`node -e` 里用 `crypto.createECDH('prime256v1')` 取 `getPublicKey()` /
`getPrivateKey()`，都转成 base64url）：

```bash
cd workers/reminder

# 1) 触发接口的令牌（防止公网上任何人拿它群发通知）
npx wrangler secret put REMIND_TOKEN

# 2) Web Push 私钥（公钥 + subject 写在 wrangler.jsonc 的 vars 里，不进 secret）
npx wrangler secret put VAPID_PRIVATE_KEY

# 3) 部署（含 cron：30 13 * * * = 21:30 北京时间）
npx wrangler deploy
```

Pages 那一侧也要配（否则浏览器拿不到公钥、订阅不了）：

```bash
cd ../..                      # 回到 Pages 项目根
# 根 wrangler.jsonc 的 vars 里已有 VAPID_PUBLIC_KEY / VAPID_SUBJECT（必须与 Worker 那份完全一致）
npx wrangler d1 migrations apply sekainook --remote   # 建 push_subscriptions 表
npm run deploy                                        # 部署站点（含 /api/push/*、sw.js 的 push 处理、设置页入口）
```

### B. 走 ntfy / bark / webhook

```bash
cd workers/reminder
npx wrangler secret put REMIND_TOKEN
npx wrangler secret put NTFY_TOPIC        # ntfy：一个够随机的主题名，如 sekainook-a7f3c91d
npx wrangler secret put BARK_KEY          # bark：Bark App 里那串 key
npx wrangler secret put PUSH_WEBHOOK_URL  # webhook：你的接收地址
npx wrangler deploy
```


其他可选配置：

| 名字 | 类型 | 说明 |
| --- | --- | --- |
| `PUSH_CHANNEL` | var | 强制通道，`ntfy` / `bark` / `webhook` / `webpush` |
| `VAPID_PUBLIC_KEY` | var | Web Push 公钥（与 Pages 项目那份必须一致） |
| `VAPID_SUBJECT` | var | `mailto:` 或 https 地址，推送服务商出问题时联系你 |
| `VAPID_PRIVATE_KEY` | secret | Web Push 私钥 |
| `NTFY_SERVER` | var | 默认 `https://ntfy.sh`；自建填自己的域名 |
| `NTFY_TOKEN` | secret | 自建 ntfy 开了鉴权 / ntfy 账号令牌时用 |
| `BARK_SERVER` | var | 默认 `https://api.day.app` |
| `PUSH_WEBHOOK_HEADERS` | secret | 额外请求头的 JSON 字符串，如 `{"X-Token":"abc"}` |
| `APP_URL` | var | 点通知打开哪个页面，默认 `https://sekainook.pages.dev/home` |
| `DRY_RUN` | var | `1` = 只算不发（本地联调用，线上别开） |

## 孩子手机上怎么收

- **webpush（默认）**：
  - **Android**：Chrome 打开 `https://sekainook.pages.dev` → 设置 → 手机提醒 → 开启提醒 →
    浏览器弹权限点「允许」。不用装任何 App。
  - **iPhone / iPad**：必须先在 **Safari** 里「分享 → 添加到主屏幕」，然后**从主屏幕图标**打开
    （iOS 16.4+ 才允许网页推送，且只有主屏 PWA 能收），再进 设置 → 手机提醒 → 开启提醒。
  - 换手机 / 清了站点数据后要重新开启一次；旧订阅失效（410）时 Worker 会自动清理。
- **ntfy**：装 **ntfy** App（Android：Play / F-Droid；iOS：App Store），App 里 **Subscribe to topic**，
  填上第 2 步那个主题名。不想装 App 也行：浏览器打开 `https://ntfy.sh/<主题名>` 就能看到消息。
  换主题名 = 重跑 `npx wrangler secret put NTFY_TOPIC` + 在手机上重新订阅。
- **bark**：App Store 装 **Bark**，打开就能看到一条形如 `https://api.day.app/XXXXXXXX/推送内容` 的示例地址，
  中间那串 `XXXXXXXX` 就是 `BARK_KEY`。通知由 Bark 自己的服务转发到这台 iPhone/iPad。

## 本地联调

```bash
cd workers/reminder
npm run dev      # = wrangler dev --test-scheduled --persist-to ../../.wrangler/state --port 8789
                 # --persist-to 指向 Pages 项目的本地 D1，所以读的是你本地那份流水
```

```bash
# 看配置是否齐（不含任何密钥明文，也不返回今天完成数——这个接口是公开的）
curl http://127.0.0.1:8789/health

# 只算不发：看今天完成几个、还差几个、文案长什么样
curl -H "Authorization: Bearer dev-token" "http://127.0.0.1:8789/trigger?dry=1"

# 假装现在是某个时刻（验证跨日/时区口径）
curl -H "Authorization: Bearer dev-token" "http://127.0.0.1:8789/trigger?dry=1&now=2026-10-15T13:30:00Z"

# 真发一条测试通知（本地 .dev.vars 里 DRY_RUN=1，用 dry=0 单次覆盖）
curl -H "Authorization: Bearer dev-token" "http://127.0.0.1:8789/trigger?test=1&dry=0"

# 指定通道真发（临时覆盖 PUSH_CHANNEL，用来逐条验证通道）
curl -H "Authorization: Bearer dev-token" "http://127.0.0.1:8789/trigger?test=1&dry=0&channel=webhook"

# 手动跑一次 cron 处理函数
curl "http://127.0.0.1:8789/__scheduled?cron=30+13+*+*+*"
```

线上同样可以手动触发（令牌就是 `REMIND_TOKEN`）：

```bash
curl -H "Authorization: Bearer <REMIND_TOKEN>" "https://sekainook-reminder.<你的子域>.workers.dev/trigger?test=1"
```

### `/trigger` 的参数

| 参数 | 作用 |
| --- | --- |
| `dry=1` | 只算不发（覆盖 `DRY_RUN`）；`dry=0` 可单次真发 |
| `force=1` | 绕过去重、即使已完成也发（验证通道用） |
| `test=1` | 发一条固定测试文案，用来确认手机能收到 |
| `channel=ntfy\|bark\|webhook\|webpush` | 临时指定通道（非法值 400） |
| `now=<ISO>` | 假装现在是这个时刻，验证跨日/时区口径 |

### 本地验 Web Push 的坑

`wrangler dev` 会把 `http_proxy` / `https_proxy` 也带上（启动日志里有
`Proxy environment variables detected`）。实测在这个环境下 **ntfy 能发出去、FCM（Web Push）会一直挂着**，
加了 15 秒超时后报 `The operation was aborted due to timeout` —— 所以 **Web Push 的端到端只能在线上验**
（线上 Worker 直连推送服务，不经本地代理）。本地想验通道就 `?channel=ntfy`，或者只跑 `?dry=1` 看判定与文案。


## 幂等：一天只打扰一次

cron 是 at-least-once，所以发送前先在 `settings` 表里抢一个标记
（`INSERT ... ON CONFLICT DO NOTHING`，key = `reminder_sent_<东八区日期>`，看 `meta.changes`）——
抢到才发，抢不到说明已经发过了。用的是现成的 key/value 表，不需要新建表。

`settings` 表还没迁移时（本地空库）不会因此不发通知：一个无关的表结构问题不该静默掐掉提醒，
出错时按「可以发」处理并把原因写进日志。

**发送失败会把标记还回去**：否则通道临时挂掉（ntfy 限流、webhook 没起来）就会把当天唯一一次机会吃掉，
之后手动 `/trigger` 补发也会被判成「今天已经提醒过」。`force=1` 本来就不抢标记，所以不会去删别人的。

## 还想加 FCM（App 内推送）怎么办

`src/channels.ts` 的 `sendPush` 是唯一出口，`reminder.ts` 不关心用的是哪条通道。要加就：

- **FCM**：Firebase 项目 + `google-services.json` + 服务账号私钥放 Worker secret，App 端接
  `firebase_messaging`。最稳（App 被杀也能收），但活儿最多 —— 适合以后 Flutter App 想在自己进程里收推送时再上。

（Web Push 已经实现好了：`src/webpush.ts` + `public/sw.js` + `functions/api/push/*` + 设置页「手机提醒」。）

## 顺带可以做的事

有了这个 cron，日结算不必再「懒执行」了：现在罚款要等下次有人打开 App 才落库，
可以把 `functions/api/ledger/settle.ts` 的那段判定搬一份到这里，在 22:05 准点结算。

## 目录

```
workers/reminder/
  wrangler.jsonc    Worker 配置（cron + D1 绑定 + vars）
  src/index.ts      scheduled（cron）+ fetch（/health、/trigger）
  src/reminder.ts   判定与发送编排（口径来自 functions/_lib/rules.ts）
  src/channels.ts   推送通道（webpush / ntfy / bark / webhook 四条）
  src/webpush.ts    Web Push：aes128gcm + VAPID，逐台发、自动清失效订阅
  src/env.ts        环境变量类型（secret 不进 wrangler.jsonc）
  tsconfig.json     独立于前端那份（只 typecheck 这个 Worker）
  .dev.vars         本地联调密钥（已 gitignore）
```
