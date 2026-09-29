---
description: SekaiNook 后端接口开发规范（Cloudflare Pages Functions + D1 + R2）。新增/修改 /api 接口、建表、前端调用时必须遵守。
alwaysApply: true
---

# SekaiNook 项目规则

## 技术栈与架构

- 前端：React 18 + Vite + TypeScript + antd / antd-mobile + zustand
- 后端：**Cloudflare Pages Functions**（文件即路由）+ **D1**（SQLite）+ **R2**（对象存储）
- 部署：`git push` → Cloudflare Pages 自动构建重部署（无需手动操作）
- 数据分层：
  - **D1 云端**：`family_ledger`（积分流水）、`weekly_plans`（每周计划）→ 跨设备共享
  - **localStorage 本地**：角色、家长密码、花园 → 各设备独立，不跨设备同步

请求链路：`浏览器 fetch('/api/...') → Pages Functions → D1 / R2`

## 目录约定

```
functions/api/            后端接口（文件路径 = URL 路径）
  ledger/index.ts         GET/POST  /api/ledger
  ledger/[id].ts          PATCH/DELETE /api/ledger/:id
  plans/index.ts          GET/POST  /api/plans
  plans/[id].ts           PATCH     /api/plans/:id
  upload.ts               POST      /api/upload
  images/[[key]].ts       GET       /api/images/:key（[[key]] 匹配含斜杠的多段）
migrations/               D1 建表 SQL（编号递增，必须幂等）
src/api/http.ts           前端 REST 客户端（唯一出口）
src/api/*.ts              前端业务接口封装
src/types/*.ts            共享类型
wrangler.jsonc            D1 / R2 绑定配置
public/_routes.json       声明 Functions 只接管 /api/*
```

## 新增一个后端接口的步骤

### 1. 建表（如需新表）→ `migrations/000X_xxx.sql`

- 文件名编号递增，如 `0002_add_rewards.sql`
- **所有语句必须幂等**：`CREATE TABLE IF NOT EXISTS` / `CREATE INDEX IF NOT EXISTS`
- 主键用 `id TEXT PRIMARY KEY`，时间戳用 `created_at TEXT NOT NULL`（存 ISO 字符串）
- 应用方式：`npm run db:migrate:local`（本地）/ `npm run db:migrate:remote`（线上）
- 若线上表已在 Dashboard 手工建过，也保持一致，重复执行不报错

### 2. 写函数 → `functions/api/<资源>/index.ts` 与 `[id].ts`

- **文件路径即路由**：`functions/api/rewards/index.ts` → `/api/rewards`
- 每个文件按需声明自己用到的绑定（不要 import 全局 Env）：

```ts
interface Env {
  DB: D1Database;
}

export const onRequestGet: PagesFunction<Env> = async ({ request, env }) => {
  const { results } = await env.DB.prepare('SELECT * FROM rewards ORDER BY created_at DESC').all();
  return Response.json(results ?? []);
};
```

- 导出的处理函数名必须是 `onRequestGet` / `onRequestPost` / `onRequestPatch` / `onRequestDelete` / `onRequestPut`
- 动态段从 `params` 取：`const id = String(params.id)`（`[id].ts`）；`[[key]].ts` 的 key 是数组，需 `.join('/')`
- 查询参数：`new URL(request.url).searchParams.get('status')`

### 3. 入参校验（必做，失败返回 400）

```ts
let body: Record<string, unknown>;
try {
  body = await request.json<Record<string, unknown>>();
} catch {
  return Response.json({ error: '请求体不是合法 JSON' }, { status: 400 });
}

const { name, type } = body;
if (typeof name !== 'string' || !name) {
  return Response.json({ error: 'name 非法' }, { status: 400 });
}
if (typeof type !== 'string' || !ALLOWED_TYPES.includes(type)) {
  return Response.json({ error: 'type 非法' }, { status: 400 });
}
```

### 4. 返回约定

| 场景 | 返回 |
| --- | --- |
| 查询成功 | `Response.json(results ?? [])` |
| 新增成功 | `Response.json({ id }, { status: 201 })` |
| 更新 / 删除成功 | `Response.json({ ok: true })` |
| 参数非法 | `Response.json({ error: 'xxx 非法' }, { status: 400 })` |
| 记录不存在 | `Response.json({ error: '记录不存在' }, { status: 404 })` |

- 更新/删除后用 `result.meta.changes` 判断是否命中记录，为 0 → 404
- 主键：`crypto.randomUUID()`；时间：`new Date().toISOString()`

### 5. 前端封装 → `src/api/<模块>.ts`

- **所有请求必须走 `src/api/http.ts`，禁止业务代码里裸写 `fetch`**
- `http.get / post / patch / delete` 已统一处理 JSON 序列化与错误归一化（失败抛 `ApiError`）
- 动态路径参数要 `encodeURIComponent(id)`

```ts
import { http } from './http';
import type { Reward } from '../types/reward';

export function fetchRewards(): Promise<Reward[]> {
  return http.get<Reward[]>('/api/rewards');
}

export async function addReward(input: { name: string }): Promise<boolean> {
  await http.post<{ id: string }>('/api/rewards', input);
  return true;
}
```

- 共享类型放 `src/types/`，字段名与 D1 表列名保持一致（snake_case）

### 6. 本地联调与部署

- 两个终端：`npm run dev`（前端 5173）+ `npm run dev:api`（wrangler 8788）
- 前端经 `vite.config.ts` 代理 `/api` → `http://127.0.0.1:8788`
- 部署：`git push` 后 Cloudflare Pages 自动构建，无需手动 deploy

## 关键约束（踩过的坑，务必遵守）

1. **代理必须用 `127.0.0.1`，不能写 `localhost`**：Node 可能解析到 IPv6 `::1`，而 workerd 只监听 IPv4 → 表现为 500/502
2. **`build` 脚本必须先跑 `wrangler types`**：`worker-configuration.d.ts` 被 gitignore，CI 上不存在，不生成会导致 `tsc` 找不到 `Env` / `PagesFunction` 类型而构建失败
3. **`public/_routes.json` 必须保持 `include: ["/api/*"]`**：否则 `public/_redirects` 的 `/* /index.html 200` 兜底会把接口请求吞成 HTML（表现为接口返回 `text/html`）
4. **不要引入鉴权中间件 / 共享口令**：本项目定位是家庭内部简单 CRUD，接口默认公开，不校验 token
5. **R2 图片读取接口保持匿名**：`<img>` 标签无法携带请求头，`/api/images/*` 不能加鉴权
6. **改动绑定要同步三处**：`wrangler.jsonc`（本地+构建）、Cloudflare Dashboard 的 Pages 绑定、函数内的 `interface Env`
7. **D1 绑定名固定为 `DB`，R2 绑定名固定为 `STARRYMIKU_BUCKET`**，不要改名

## 校验清单（提交前自查）

- [ ] 新增 SQL 全部幂等，本地 `db:migrate:local` 通过
- [ ] 函数导出名正确（`onRequestXxx`），`tsc --noEmit` 无报错
- [ ] 前端走 `http.ts`，未裸写 `fetch`
- [ ] `npm run build` 通过（含 `wrangler types`）
- [ ] 本地 5173 经代理实测接口 200
