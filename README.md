# SekaiNook（Flutter 版）

家庭「行为 ↔ 积分银行」App 的 Flutter 客户端。**复用 Web 版同一套 Cloudflare Pages Functions 后端**
（`https://sekainook.pages.dev`），业务语义完全一致，只是把前端从 React + antd 换成 Flutter。

- 姊妹仓库（Web 版 + 后端）：`E:\Git\SekaiNook`
- 目标平台：**Android 手机** + **Flutter Web**（同一份代码）

## 跑起来

```bash
flutter pub get

# 连线上后端（默认）
flutter run -d chrome

# 连本地后端（Web 版仓库里 `npm run dev:api` 起的 8788）
flutter run -d chrome --dart-define=API_BASE=http://127.0.0.1:8788

# Android 真机 / 模拟器
flutter run -d <device-id>
```

`API_BASE` 是编译期常量，默认值在 `lib/config/app_constants.dart`。

### 本地后端

后端代码在 Web 版仓库，本地起服务的步骤：

```bash
cd E:\Git\SekaiNook
npm run dev:api          # wrangler pages dev public --port 8788
```

> 浏览器里 Flutter Web 连本地后端需要 CORS。Web 版仓库已加 `functions/_middleware.ts`
> （**只补 CORS 响应头 + 应答 OPTIONS 预检，不鉴权、不改状态码与响应体**）。

## 平台开关

| 平台 | 命令 | 备注 |
| --- | --- | --- |
| Web | `flutter build web --dart-define=API_BASE=...` | 产物在 `build/web` |
| Android | `flutter build apk --release` | 产物在 `build/app/outputs/flutter-apk/` |

## 目录结构

```
lib/
  main.dart              入口：建 SharedPreferences → 建各 store → runApp
  app.dart               MaterialApp.router + Provider 注入 + 启动加载
  router.dart            go_router 路由表（对应 Web 版 src/App.tsx）
  config/                业务规则常量（family_rules / garden_config / app_constants）
  core/                  api_client(dio) / api_exception / pin_guard / task_rules / week / image_compress / ledger_ids
  data/api/              接口层：ledger / plans / notifications / settings / admin / upload / maintenance
  data/models/           数据模型
  state/                 全局状态（ChangeNotifier）：family / theme / settings / notification / customTasks / garden
  theme/                 tokens（间距圆角字号）+ app_theme（7 套主题色板）
  ui/shell/              底部导航骨架 MainShell（含 15 秒通知轮询）
  ui/pages/              页面：home(妹妹版/妈妈版/通知) / family(工作台/周计划) / garden / settings / role_gate
  ui/widgets/            通用卡片、状态视图
docs/                    接口契约与移植说明（见下）
```

## 契约文档（写代码前先查这里）

| 文件 | 内容 |
| --- | --- |
| [docs/api-contract.md](docs/api-contract.md) | 全部 19 个接口的字段级契约、任务规则总表、防刷闸门、日结算、数据表结构、80 条 Dart 易踩的坑、81 项验收清单 |
| [docs/contract-garden-store.md](docs/contract-garden-store.md) | 花园 store（阳光/勋章/商城/古诗/语文）的持久化格式、日切规则、逐函数逻辑、33 条坑 |
| [docs/contract-other-stores.md](docs/contract-other-stores.md) | 通知 / 主题 / 设置 / 自定义任务四个 store 的行为契约与持久化键 |

## 与 Web 版的差异（有意为之）

1. **本地存储**：Web 版用 `localStorage`，Flutter 用 `shared_preferences`。
   键名保持一致，便于对照；Web 版与 Flutter Web 在同一浏览器里并不共享存储区，互不影响。
2. **家长口令**：Web 版在非安全上下文（http 打开）会把口令降级为明文存储；
   Dart 的 `crypto` 任何环境都能算摘要，所以 Flutter 侧**一律存摘要**，
   但**读取**仍兼容 Web 版留下的 `plain:` 前缀与无前缀裸明文。
3. **上传**：Web 版 `fetch` 直接发 `arrayBuffer`；Flutter 侧对应 `ApiClient.postBytes`，
   同样发裸二进制（**不是 multipart**）。
4. **图表**：Web 版用 echarts，Flutter 用 `fl_chart`。
5. **通知轮询**：间隔与 Web 版一致（15 秒），且在应用退到后台时跳过。
