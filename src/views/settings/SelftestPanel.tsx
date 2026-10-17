import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  Alert,
  Button,
  Card,
  Checkbox,
  Collapse,
  Input,
  InputNumber,
  Modal,
  Progress,
  Select,
  Space,
  Switch,
  Tag,
  Tooltip,
  message,
} from "antd";
import {
  CheckCircleFilled,
  CloseCircleFilled,
  CopyOutlined,
  DownloadOutlined,
  ExperimentOutlined,
  MinusCircleFilled,
  PlayCircleOutlined,
  ReloadOutlined,
  SafetyCertificateOutlined,
  StopOutlined,
  ThunderboltOutlined,
  WarningFilled,
} from "@ant-design/icons";
import type { ComponentType, ReactNode } from "react";
import { createRoot } from "react-dom/client";
import { MemoryRouter } from "react-router-dom";
import { http } from "../../api/http";
import { useFamilyStore } from "../../store/useFamilyStore";
import { useThemeStore } from "../../store/useThemeStore";
import { THEMES } from "../../theme/themes";
import { isIosNeedsInstall } from "../../utils/push";
import styles from "./SettingsPage.module.css";

/**
 * 全站自检面板 —— 挂在「设置 → 管理员」里面，复用那道已经解开的密码。
 *
 * 为什么长这样（契约见 docs/selftest-console.md）：
 * ① 检查项分两侧。`side === "server"` 的由 `POST /api/admin/selftest` 跑；
 *    `side === "client"` 的服务端一律不跑（只回一条 skip: client-side），必须由
 *    本页先跑出来、随请求一起用 clientResults 回传覆盖。所以「运行」是两段：
 *    先本地跑 web.* 六项，再 POST。
 * ② 会写库的项（mutates）默认不勾，勾了也要二次确认 —— 有些项真会写一行流水、
 *    真会发一条通知出去。keep 默认关（跑完自清理），dryRun 默认开。
 * ③ 单次 POST 一次性返回整批结果，所以「中途停止」只对本地那六项是真的停，
 *    服务端那批只能停止等待（结果不再回填）—— 界面上照实说。
 *
 * 复用 SettingsPage.module.css，不新建样式文件；只用现有依赖。
 */

/* ===== 契约类型（照 docs/selftest-console.md 抄，不做业务口径的二次加工） ===== */

type SelftestStatus = "pass" | "fail" | "warn" | "skip";
type SelftestSide = "server" | "client";
type ParamValue = string | number | boolean;

interface SelftestItem {
  id: string;
  name: string;
  desc: string;
  side: SelftestSide;
  client: "web" | "flutter" | null;
  mutates: boolean;
  danger: "safe" | "write" | "destructive";
  params: string[];
  estMs: number;
}

interface SelftestGroup {
  id: string;
  name: string;
  desc?: string;
  items: SelftestItem[];
}

interface SelftestParam {
  name: string;
  label: string;
  type: "bool" | "int" | "string" | "enum";
  desc?: string;
  options?: string[];
  default?: ParamValue;
}

interface SelftestPreset {
  id: string;
  name: string;
  desc?: string;
  itemIds?: string[];
  params?: Record<string, ParamValue>;
  skipMutating?: boolean;
}

interface SelftestManifest {
  version: number;
  generatedAt: string;
  groups: SelftestGroup[];
  params: SelftestParam[];
  presets: SelftestPreset[];
  clientChecks?: { web?: string[]; flutter?: string[] } | null;
}

interface SelftestClientResult {
  id: string;
  status: SelftestStatus;
  detail: string;
  ms?: number;
  data?: unknown;
}

interface SelftestResultRow {
  id: string;
  name?: string;
  group?: string;
  side?: SelftestSide;
  status: SelftestStatus;
  ms?: number;
  detail?: string;
  data?: unknown;
  hint?: string;
}

interface SelftestSummary {
  total: number;
  passed: number;
  failed: number;
  skipped: number;
  warned: number;
}

interface SelftestRunResponse {
  version?: number;
  ranAt: string;
  durationMs: number;
  env?: { db?: string; origin?: string; now?: string; worker?: string };
  summary: SelftestSummary;
  results: SelftestResultRow[];
  notes?: string[];
  clientMissing?: string[];
}

/** 客户端检查的产出（比 SelftestClientResult 少一个 id，由调用方补） */
interface ClientOutcome {
  status: SelftestStatus;
  detail: string;
  data?: unknown;
}

/* ===== 状态外观 ===== */

const STATUS_META: Record<SelftestStatus, { label: string; tag: string; mark: string; icon: ReactNode }> = {
  pass: { label: "通过", tag: "success", mark: "✅", icon: <CheckCircleFilled /> },
  fail: { label: "失败", tag: "error", mark: "❌", icon: <CloseCircleFilled /> },
  warn: { label: "留意", tag: "warning", mark: "⚠️", icon: <WarningFilled /> },
  skip: { label: "跳过", tag: "default", mark: "⏭️", icon: <MinusCircleFilled /> },
};

/** 失败最前（契约要求），其余保持服务端给的顺序 */
function statusRank(status: SelftestStatus): number {
  if (status === "fail") return 0;
  if (status === "warn") return 1;
  return 2;
}

/* ===== 小工具 ===== */

function errText(err: unknown): string {
  if (err instanceof Error) return err.message;
  if (typeof err === "string") return err;
  return String(err);
}

function pad2(n: number): string {
  return String(n).padStart(2, "0");
}

/** 本地时间 `2026-10-17 18:00:01` */
function formatClock(input: string | number | Date): string {
  const d = input instanceof Date ? input : new Date(input);
  if (Number.isNaN(d.getTime())) return typeof input === "string" ? input : "—";
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ${pad2(d.getHours())}:${pad2(
    d.getMinutes(),
  )}:${pad2(d.getSeconds())}`;
}

/** 契约里的时间格式：`2026-10-17 18:00:01 (+08:00)` */
function formatRunTime(input: string | number | Date): string {
  const d = input instanceof Date ? input : new Date(input);
  if (Number.isNaN(d.getTime())) return typeof input === "string" ? input : "—";
  const offset = -d.getTimezoneOffset();
  const sign = offset >= 0 ? "+" : "-";
  const abs = Math.abs(offset);
  return `${formatClock(d)} (${sign}${pad2(Math.floor(abs / 60))}:${pad2(abs % 60)})`;
}

function fileStamp(d = new Date()): string {
  return `${d.getFullYear()}${pad2(d.getMonth() + 1)}${pad2(d.getDate())}-${pad2(d.getHours())}${pad2(
    d.getMinutes(),
  )}${pad2(d.getSeconds())}`;
}

/** `https://sekainook-reminder.xxx.workers.dev` → `sekainook-reminder`（契约的示例写法） */
function workerLabel(worker?: string): string {
  if (!worker) return "";
  const host = worker.replace(/^https?:\/\//, "").split("/")[0];
  return host.split(".")[0] || host;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

/** `#rrggbb` 的相对亮度（0 黑 1 白）；不是十六进制就返回 null（主题可以用任何颜色写法） */
function luminance(color: string): number | null {
  const matched = /^#([0-9a-f]{6})$/i.exec(color.trim());
  if (!matched) return null;
  const value = Number.parseInt(matched[1], 16);
  const r = ((value >> 16) & 0xff) / 255;
  const g = ((value >> 8) & 0xff) / 255;
  const b = (value & 0xff) / 255;
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

async function copyText(text: string): Promise<boolean> {
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch {
    // 非安全上下文 / 没给权限：落到下面的 textarea 方案
  }
  try {
    const area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "true");
    area.style.position = "fixed";
    area.style.left = "-10000px";
    document.body.appendChild(area);
    area.select();
    const ok = document.execCommand("copy");
    area.remove();
    return ok;
  } catch {
    return false;
  }
}

/* ===== 客户端六项 ===== */

/**
 * 7 个入口逐个「模块能加载 + 能在隐藏容器里渲出内容」。
 *
 * 这是真渲染（createRoot + MemoryRouter），不是假断言；但**不做地址跳转** ——
 * 本面板自己就在路由树里，navigate 过去会把这面板卸掉。
 * 没有 /role 这条路由（身份门 RoleGate 是 App 直接渲染的），所以它按组件直接渲。
 */
const ROUTE_CHECKS: readonly {
  path: string;
  label: string;
  load: () => Promise<{ default: ComponentType }>;
}[] = [
  { path: "/home", label: "首页", load: () => import("../home/HomePage") },
  { path: "/home/notifications", label: "通知", load: () => import("../home/NotificationsPage") },
  { path: "/family", label: "家庭", load: () => import("../family/FamilyDashboard") },
  { path: "/family/plan", label: "周计划", load: () => import("../family/WeeklyPlan") },
  { path: "/garden", label: "花园", load: () => import("../../layouts/GardenLayout") },
  { path: "/settings", label: "设置", load: () => import("./SettingsPage") },
  { path: "/role", label: "身份门", load: () => import("../../components/RoleGate") },
];

async function checkRoutes(): Promise<ClientOutcome> {
  const ok: string[] = [];
  const bad: string[] = [];
  const seenErrors: string[] = [];
  const onError = (event: ErrorEvent) => {
    seenErrors.push(event.message || errText(event.error));
  };
  window.addEventListener("error", onError);
  try {
    for (const route of ROUTE_CHECKS) {
      let page: ComponentType | null = null;
      try {
        const mod = await route.load();
        if (typeof mod.default === "function") page = mod.default;
      } catch (err) {
        bad.push(`${route.path}（模块加载失败：${errText(err)}）`);
        continue;
      }
      if (page === null) {
        bad.push(`${route.path}（没有默认导出）`);
        continue;
      }

      const host = document.createElement("div");
      host.setAttribute("aria-hidden", "true");
      host.style.position = "fixed";
      host.style.left = "-10000px";
      host.style.top = "0";
      host.style.width = "360px";
      host.style.pointerEvents = "none";
      document.body.appendChild(host);
      const errorsBefore = seenErrors.length;
      const root = createRoot(host);
      const Page = page;
      try {
        root.render(
          <MemoryRouter initialEntries={[route.path]}>
            <Page />
          </MemoryRouter>,
        );
        // 等 React 提交一帧（StrictMode 下 effect 会跑两遍，但这里不在 StrictMode 里）
        await sleep(140);
        const text = (host.textContent ?? "").trim();
        if (text.length === 0) bad.push(`${route.path}（渲染完没有内容）`);
        else ok.push(`${route.label}${route.path}(${text.length} 字)`);
      } catch (err) {
        bad.push(`${route.path}（渲染抛错：${errText(err)}）`);
      } finally {
        try {
          root.unmount();
        } catch {
          // 卸载失败不影响这一项的结论
        }
        host.remove();
      }
      if (seenErrors.length > errorsBefore) {
        bad.push(`${route.path}（控制台报错：${seenErrors[errorsBefore]}）`);
      }
    }
  } finally {
    window.removeEventListener("error", onError);
  }

  const data = { ok, bad, errors: seenErrors, total: ROUTE_CHECKS.length };
  if (bad.length > 0) {
    return {
      status: "fail",
      detail: `${ok.length}/${ROUTE_CHECKS.length} 个入口能渲染，${bad.length} 个有问题：${bad.join("；")}`,
      data,
    };
  }
  return {
    status: "pass",
    detail: `${ROUTE_CHECKS.length} 个入口模块都能加载并在隐藏容器里渲出内容（不做地址跳转，跳过去会卸掉本面板）`,
    data,
  };
}

/**
 * 7 套主题的 CSS 变量。
 *
 * 故意**不走 setThemeId** —— 那会写 localStorage（rememberBrightness 会顺手改浅/深记忆）
 * 还会让 App 重渲染，为了自检去动用户设置不正常。
 * 这里直接改 documentElement 的 data-theme 读计算值，整轮同步跑完，浏览器只在最后绘制一次，
 * 所以不会闪；finally 一定还原。
 */
async function checkTheme(): Promise<ClientOutcome> {
  const root = document.documentElement;
  const original = root.getAttribute("data-theme");
  const storeTheme = useThemeStore.getState().themeId;
  const rows: { id: string; name: string; dark: boolean; bg: string; text: string; primary: string }[] = [];
  const empty: string[] = [];
  const suspicious: string[] = [];
  try {
    for (const preset of THEMES) {
      root.setAttribute("data-theme", preset.id);
      const computed = getComputedStyle(root);
      const bg = computed.getPropertyValue("--color-bg").trim();
      const text = computed.getPropertyValue("--color-text").trim();
      const primary = computed.getPropertyValue("--color-primary").trim();
      if (!bg || !text || !primary) empty.push(`${preset.name}(${!bg ? "--color-bg " : ""}${!text ? "--color-text " : ""}${!primary ? "--color-primary" : ""})`);
      rows.push({ id: preset.id, name: preset.name, dark: preset.dark, bg, text, primary });
      const bright = luminance(bg);
      if (bright !== null && preset.dark && bright > 0.6) suspicious.push(`${preset.name} 标着深色但底色很亮(${bg})`);
      if (bright !== null && !preset.dark && bright < 0.25) suspicious.push(`${preset.name} 标着浅色但底色很暗(${bg})`);
    }
  } finally {
    if (original === null) root.removeAttribute("data-theme");
    else root.setAttribute("data-theme", original);
  }

  const distinct = new Set(rows.map((r) => r.bg)).size;
  const data = { themes: rows, distinctBackgrounds: distinct, storeTheme, attr: original };

  if (empty.length > 0) {
    return { status: "fail", detail: `有主题没读到 CSS 变量：${empty.join("、")}`, data };
  }
  if (distinct < 2) {
    return { status: "fail", detail: `7 套主题底色只有 ${distinct} 种，data-theme 切了但变量没变`, data };
  }
  if (original !== null && storeTheme !== original) {
    return {
      status: "warn",
      detail: `7 套主题变量都在（${distinct} 种底色），但设置里存的是 ${storeTheme}、页面上是 ${original}，两边对不上`,
      data,
    };
  }
  if (suspicious.length > 0) {
    return { status: "warn", detail: `7 套主题变量都在（${distinct} 种底色），深浅标记可疑：${suspicious.join("、")}`, data };
  }
  return { status: "pass", detail: `7 套主题都能读到 --color-bg/--color-text/--color-primary（${distinct} 种底色，浅深与标记一致）`, data };
}

async function checkServiceWorker(): Promise<ClientOutcome> {
  if (!("serviceWorker" in navigator)) {
    return { status: "fail", detail: "这个浏览器没有 Service Worker，离线缓存与推送都用不了" };
  }
  const prod = import.meta.env.PROD;
  const registrations = await navigator.serviceWorker.getRegistrations();
  const scoped =
    registrations.find((reg) => {
      const script = reg.active?.scriptURL ?? reg.waiting?.scriptURL ?? reg.installing?.scriptURL ?? "";
      return script.endsWith("/sw.js");
    }) ?? registrations[0];
  const data = {
    prod,
    registrations: registrations.length,
    scope: scoped?.scope ?? null,
    state: scoped?.active?.state ?? scoped?.installing?.state ?? null,
    script: scoped?.active?.scriptURL ?? scoped?.installing?.scriptURL ?? null,
    controlled: navigator.serviceWorker.controller?.scriptURL ?? null,
    pushManager: typeof PushManager !== "undefined",
  };

  if (!scoped) {
    return prod
      ? { status: "fail", detail: "生产环境下没有注册 /sw.js，离线缓存和推送都收不到", data }
      : { status: "warn", detail: "开发模式不注册 SW（src/main.tsx 只在 PROD 里注册），属预期", data };
  }
  if (typeof PushManager === "undefined") {
    return { status: "warn", detail: `已注册（scope ${scoped.scope}），但这个浏览器没有 PushManager`, data };
  }
  return {
    status: "pass",
    detail: `已注册 ${scoped.scope}（${scoped.active?.state ?? "未激活"}），push 能力可用`,
    data,
  };
}

async function checkPush(): Promise<ClientOutcome> {
  if (typeof PushManager === "undefined") {
    return { status: "fail", detail: "这个浏览器没有 PushManager，收不到 Web 推送" };
  }
  const permission = typeof Notification === "undefined" ? "unsupported" : Notification.permission;
  const iosNeedsInstall = isIosNeedsInstall();
  let subscribed = false;
  let endpointHost = "";
  if ("serviceWorker" in navigator) {
    const reg = await navigator.serviceWorker.getRegistration();
    const sub = reg ? await reg.pushManager.getSubscription() : null;
    subscribed = sub !== null;
    if (sub) {
      try {
        endpointHost = new URL(sub.endpoint).host;
      } catch {
        endpointHost = "endpoint 解析不了";
      }
    }
  }
  const data = { permission, subscribed, iosNeedsInstall, endpointHost };

  if (iosNeedsInstall) {
    return { status: "warn", detail: "iPhone / iPad 上还没「添加到主屏幕」，先加进去才收得到推送", data };
  }
  if (permission === "denied") {
    return { status: "warn", detail: "推送权限被拒绝了，要去浏览器/系统设置里放行", data };
  }
  if (!subscribed) {
    return {
      status: "warn",
      detail: `本机还没订阅推送（权限 ${permission}）—— 设置里点「开启手机提醒」后会变成已订阅，这条不算坏`,
      data,
    };
  }
  return {
    status: "pass",
    detail: `已订阅（权限 ${permission}${endpointHost ? `，endpoint 落在 ${endpointHost}` : ""}）`,
    data,
  };
}

async function checkStorage(): Promise<ClientOutcome> {
  const probe = "sekainook_selftest_probe";
  try {
    const existing = localStorage.getItem(probe);
    localStorage.setItem(probe, "ok");
    const wrote = localStorage.getItem(probe);
    localStorage.removeItem(probe);
    const cleaned = localStorage.getItem(probe) === null;
    const stored = Object.keys(localStorage).filter((key) => key.startsWith("sekainook_")).sort();
    const data = {
      wroteBack: wrote,
      cleaned,
      probeWasThere: existing !== null,
      sekainookKeys: stored,
      totalKeys: Object.keys(localStorage).length,
    };
    if (wrote !== "ok" || !cleaned) {
      return { status: "fail", detail: "localStorage 写进去读不回来 / 删不掉（隐私模式或存储被禁用？）", data };
    }
    return { status: "pass", detail: `读写删都正常；sekainook_* 键 ${stored.length} 个（本域共 ${data.totalKeys} 个键）`, data };
  } catch (err) {
    return { status: "fail", detail: `localStorage 用不了：${errText(err)}` };
  }
}

/**
 * 数据源导出。
 *
 * 故意**不调 exportLedgerCsv**（src/utils/exportLedger.ts）——那个函数会立刻触发下载，
 * 契约里写明了这条检查不触发下载。这里只把同样的字段拼成文本、量一下字节数。
 */
async function checkExport(): Promise<ClientOutcome> {
  let records = useFamilyStore.getState().records;
  let refreshed = false;
  if (records.length === 0) {
    try {
      await useFamilyStore.getState().loadLedger();
      refreshed = true;
    } catch {
      // 拉不到就按现有的（也可能确实是空的）算
    }
    records = useFamilyStore.getState().records;
  }

  const header = ["时间", "任务", "类型", "积分", "状态", "备注", "图片"];
  const cell = (value: string) => `"${value.replace(/"/g, '""')}"`;
  const rows = records.map((r) => [
    new Date(r.created_at).toLocaleString("zh-CN"),
    r.task_name,
    r.type === "earning" ? "赚钱" : "消费/罚款",
    String(r.amount),
    r.status === "pending" ? "待审批" : r.status === "rejected" ? "已驳回" : "已入账",
    (r.note ?? "").replace(/[\r\n]+/g, " "),
    r.image_url ?? "",
  ]);
  const csv = [header, ...rows].map((cells) => cells.map(cell).join(",")).join("\r\n");
  const json = JSON.stringify(records);
  const encoder = new TextEncoder();
  const data = {
    count: records.length,
    refreshed,
    csvBytes: encoder.encode(csv).length,
    jsonBytes: encoder.encode(json).length,
    csvHeader: header.join(","),
    sample: rows.length > 0 ? rows[0].join(" , ") : null,
  };

  if (records.length === 0) {
    return { status: "warn", detail: "一条流水都没有，CSV/JSON 只能生成表头 —— 生成链路本身是通的", data };
  }
  return {
    status: "pass",
    detail: `${records.length} 条流水能生成 CSV(${data.csvBytes} 字节) 与 JSON(${data.jsonBytes} 字节)，没有触发下载`,
    data,
  };
}

const CLIENT_CHECKS: Record<string, () => Promise<ClientOutcome>> = {
  "web.routes": checkRoutes,
  "web.theme": checkTheme,
  "web.sw": checkServiceWorker,
  "web.push": checkPush,
  "web.storage": checkStorage,
  "web.export": checkExport,
};

/** 清单里没给 clientChecks 时的兜底（契约固定这六个 id） */
const WEB_CLIENT_IDS: readonly string[] = Object.keys(CLIENT_CHECKS);

async function runOneClientCheck(id: string): Promise<SelftestClientResult> {
  const startedAt = Date.now();
  const fn = CLIENT_CHECKS[id];
  if (!fn) {
    return { id, status: "skip", ms: 0, detail: "这个客户端项本页没实现，交给服务端标 skip" };
  }
  try {
    const outcome = await fn();
    return { id, status: outcome.status, detail: outcome.detail, data: outcome.data, ms: Date.now() - startedAt };
  } catch (err) {
    return { id, status: "fail", ms: Date.now() - startedAt, detail: `本地跑挂了：${errText(err)}` };
  }
}

/* ===== 导出（JSON 文件下载 / Markdown 复制，格式照契约 §5） ===== */

function buildMarkdown(
  report: SelftestRunResponse,
  params: Record<string, ParamValue>,
  groupName: (id: string) => string,
): string {
  const summary = report.summary;
  const env = report.env ?? {};
  const paramText =
    Object.entries(params)
      .filter(([, value]) => value !== undefined && value !== null && value !== "")
      .map(([key, value]) => `${key}=${String(value)}`)
      .join(", ") || "（默认）";
  const origin = env.origin || window.location.origin;
  const worker = workerLabel(env.worker);
  const cell = (value: string) => value.replace(/\|/g, "\\|").replace(/[\r\n]+/g, " ");
  const rows = [...report.results].sort((a, b) => statusRank(a.status) - statusRank(b.status));

  const lines = [
    "# SekaiNook 自检报告",
    `- 时间：${formatRunTime(report.ranAt)}`,
    `- 环境：${origin}${worker ? ` · Worker ${worker}` : ""}${env.db ? ` · DB ${env.db}` : ""}`,
    `- 参数：${paramText}`,
    `- 结果：${summary.total} 项 · 通过 ${summary.passed} · 失败 ${summary.failed} · 跳过 ${summary.skipped}` +
      (summary.warned > 0 ? ` · 留意 ${summary.warned}` : ""),
    "",
    "| 结果 | 分组 | 检查项 | 耗时 | 详情 |",
    "| --- | --- | --- | --- | --- |",
    ...rows.map(
      (row) =>
        `| ${STATUS_META[row.status]?.mark ?? ""} | ${cell(groupName(row.group ?? ""))} | ${cell(
          row.name || row.id,
        )} | ${row.ms ?? 0}ms | ${cell(row.detail ?? "")} |`,
    ),
  ];
  return lines.join("\n");
}

/* ===== 参数控件 ===== */

function ParamControl({
  def,
  value,
  onChange,
}: {
  def: SelftestParam;
  value: ParamValue | undefined;
  onChange: (value: ParamValue | undefined) => void;
}) {
  if (def.type === "bool") {
    return <Switch size="small" checked={value === true} onChange={(checked) => onChange(checked)} />;
  }
  if (def.type === "int") {
    return (
      <InputNumber
        style={{ width: "100%" }}
        placeholder="默认"
        value={typeof value === "number" ? value : undefined}
        onChange={(next) => onChange(typeof next === "number" ? next : undefined)}
      />
    );
  }
  if (def.type === "enum") {
    return (
      <Select
        style={{ width: "100%" }}
        placeholder="默认"
        allowClear
        value={typeof value === "string" && value !== "" ? value : undefined}
        options={(def.options ?? []).map((option) => ({ value: option, label: option }))}
        onChange={(next) => onChange(typeof next === "string" ? next : undefined)}
      />
    );
  }
  return (
    <Input
      allowClear
      placeholder={def.desc ? "留空 = 用真实值" : "默认"}
      value={typeof value === "string" ? value : ""}
      onChange={(event) => onChange(event.target.value)}
    />
  );
}

/* ===== 面板本体 ===== */

export interface SelftestPanelProps {
  /** 已经解开的管理员密码，原样交给 POST /api/admin/selftest */
  password: string;
}

export default function SelftestPanel({ password }: SelftestPanelProps) {
  const [manifest, setManifest] = useState<SelftestManifest | null>(null);
  const [manifestError, setManifestError] = useState("");
  const [loadingManifest, setLoadingManifest] = useState(false);
  const [selected, setSelected] = useState<ReadonlySet<string>>(() => new Set<string>());
  const [params, setParams] = useState<Record<string, ParamValue>>({});
  const [openGroups, setOpenGroups] = useState<string[]>([]);
  const [openParams, setOpenParams] = useState<string[]>([]);
  const [running, setRunning] = useState(false);
  const [stopped, setStopped] = useState(false);
  const [phaseText, setPhaseText] = useState("");
  const [phasePercent, setPhasePercent] = useState(0);
  const [elapsed, setElapsed] = useState(0);
  const [clientResults, setClientResults] = useState<SelftestClientResult[]>([]);
  const [report, setReport] = useState<SelftestRunResponse | null>(null);
  const [modal, modalContextHolder] = Modal.useModal();
  /** 每一轮运行一个号；停止 / 卸载就是把号加一，晚到的结果全部丢弃 */
  const runSeq = useRef(0);

  const initParams = useCallback((defs: SelftestParam[]): Record<string, ParamValue> => {
    const next: Record<string, ParamValue> = {};
    for (const def of defs) {
      if (def.default !== undefined) next[def.name] = def.default;
    }
    return next;
  }, []);

  const loadManifest = useCallback(
    async (resetSelection: boolean) => {
      setLoadingManifest(true);
      setManifestError("");
      try {
        const data = await http.get<SelftestManifest>("/api/admin/selftest");
        setManifest(data);
        setParams(initParams(data.params));
        if (resetSelection) {
          const all = data.groups.flatMap((group) => group.items);
          setSelected(new Set(all.filter((item) => !item.mutates).map((item) => item.id)));
        }
      } catch (err) {
        setManifestError(errText(err));
      } finally {
        setLoadingManifest(false);
      }
    },
    [initParams],
  );

  useEffect(() => {
    void loadManifest(true);
  }, [loadManifest]);

  // 面板被关掉（返回上层）时把号加一，防止迟到的 POST 回来 setState
  useEffect(
    () => () => {
      runSeq.current += 1;
    },
    [],
  );

  const allItems = useMemo(
    () => (manifest ? manifest.groups.flatMap((group) => group.items) : []),
    [manifest],
  );
  const itemById = useMemo(() => new Map(allItems.map((item) => [item.id, item])), [allItems]);
  const groupNameById = useMemo(
    () => new Map((manifest?.groups ?? []).map((group) => [group.id, group.name])),
    [manifest],
  );
  const selectedItems = useMemo(() => allItems.filter((item) => selected.has(item.id)), [allItems, selected]);
  const mutatingSelected = selectedItems.filter((item) => item.mutates);
  const mutatingTotal = allItems.filter((item) => item.mutates).length;
  const failedTotal = report ? report.summary.failed : 0;

  const activeParams = useMemo(() => {
    const next: Record<string, ParamValue> = {};
    for (const [key, value] of Object.entries(params)) {
      if (value === undefined || value === null || value === "") continue;
      next[key] = value;
    }
    return next;
  }, [params]);

  const paramText = useMemo(
    () =>
      Object.entries(activeParams)
        .map(([key, value]) => `${key}=${String(value)}`)
        .join(", ") || "（全部用后端默认）",
    [activeParams],
  );

  const orderedResults = useMemo(() => {
    const rows = report?.results ?? [];
    return [...rows].sort((a, b) => statusRank(a.status) - statusRank(b.status));
  }, [report]);

  const setParam = (name: string, value: ParamValue | undefined) => {
    setParams((prev) => {
      const next = { ...prev };
      if (value === undefined) delete next[name];
      else next[name] = value;
      return next;
    });
  };

  const toggleItem = (id: string, on: boolean) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (on) next.add(id);
      else next.delete(id);
      return next;
    });
  };

  const setGroupSelected = (group: SelftestGroup, on: boolean) => {
    setSelected((prev) => {
      const next = new Set(prev);
      for (const item of group.items) {
        if (on) next.add(item.id);
        else next.delete(item.id);
      }
      return next;
    });
  };

  const selectAll = (on: boolean) => {
    setSelected(on ? new Set(allItems.map((item) => item.id)) : new Set<string>());
  };

  const applyPreset = (preset: SelftestPreset) => {
    if (preset.skipMutating) {
      setSelected(new Set(allItems.filter((item) => !item.mutates).map((item) => item.id)));
    } else if (preset.itemIds && preset.itemIds.length > 0) {
      setSelected(new Set(preset.itemIds.filter((id) => itemById.has(id))));
    } else if (preset.id === "all") {
      setSelected(new Set(allItems.map((item) => item.id)));
    }
    const patch = preset.params;
    if (patch) {
      setParams((prev) => ({ ...prev, ...patch }));
      setOpenParams(["params"]);
    }
    message.success(`已套用预设「${preset.name}」`);
  };

  const stopRun = () => {
    runSeq.current += 1;
    setRunning(false);
    setStopped(true);
    setPhaseText("");
    setPhasePercent(0);
    message.info("已停止：本地那几项立刻停；已经发出去的服务端那批还会跑完，但结果不再回填");
  };

  const runNow = useCallback(
    async (ids: string[]) => {
      if (running) return;
      if (!password) {
        message.warning("管理员密码不在了，回上一层重新解锁再跑");
        return;
      }
      if (ids.length === 0) {
        message.warning("一项都没勾");
        return;
      }
      const seq = runSeq.current + 1;
      runSeq.current = seq;
      setRunning(true);
      setStopped(false);
      setReport(null);
      setClientResults([]);
      setPhasePercent(0);
      setPhaseText("");
      const startedAt = Date.now();
      setElapsed(0);
      const timer = window.setInterval(() => setElapsed(Date.now() - startedAt), 200);

      const webIds = (manifest?.clientChecks?.web ?? WEB_CLIENT_IDS).filter((id) => ids.includes(id));
      const collected: SelftestClientResult[] = [];
      try {
        // ① 客户端自检：只有这几项能在浏览器里跑，服务端只会给它们标 skip
        for (let index = 0; index < webIds.length; index += 1) {
          if (runSeq.current !== seq) return;
          const id = webIds[index];
          setPhaseText(`客户端自检 ${index + 1}/${webIds.length}：${itemById.get(id)?.name ?? id}`);
          setPhasePercent(webIds.length > 0 ? Math.round((index / webIds.length) * 40) : 5);
          const outcome = await runOneClientCheck(id);
          collected.push(outcome);
          setClientResults([...collected]);
        }
        if (runSeq.current !== seq) return;

        // ② 剩下的交给服务端，一次 POST 全跑完再回
        setPhaseText(`服务端检查 ${ids.length} 项（跑完才回结果，别急）`);
        setPhasePercent(webIds.length > 0 ? 55 : 15);
        const response = await http.post<SelftestRunResponse>(
          "/api/admin/selftest",
          { password, items: ids, params: activeParams, clientResults: collected },
          { timeoutMs: 180000 },
        );
        if (runSeq.current !== seq) return;
        setReport(response);
        setPhasePercent(100);
        if (response.summary.failed > 0) {
          message.error(`跑完 ${response.summary.total} 项：失败 ${response.summary.failed} 项，看下面标红的`);
        } else {
          message.success(
            `跑完 ${response.summary.total} 项：全通过${response.summary.warned > 0 ? `，${response.summary.warned} 项要留意` : ""}`,
          );
        }
      } catch (err) {
        if (runSeq.current === seq) message.error(errText(err));
      } finally {
        window.clearInterval(timer);
        if (runSeq.current === seq) {
          setRunning(false);
          setPhaseText("");
          setPhasePercent(0);
        }
      }
    },
    [activeParams, itemById, manifest, password, running],
  );

  /** 勾了会写库的项就先问一句，其余直接跑 */
  const requestRun = (ids: string[]) => {
    const mutating = ids.filter((id) => itemById.get(id)?.mutates);
    if (mutating.length === 0) {
      void runNow(ids);
      return;
    }
    const preview = mutating.slice(0, 6).join("、");
    modal.confirm({
      title: `确认跑这 ${mutating.length} 个会写库的检查？`,
      okText: "跑",
      cancelText: "先不跑",
      okButtonProps: { danger: true },
      content: (
        <div style={{ fontSize: 13, lineHeight: 1.7 }}>
          <div>
            会真的动数据 / 真发通知：{preview}
            {mutating.length > 6 ? " …" : ""}
          </div>
          <div style={{ marginTop: 8, color: "var(--color-text-tertiary)" }}>
            预演 dryRun {params.dryRun === false ? "已关掉 —— 会真的落库" : "开着 —— 只算不落"}；跑完默认自清理
            （keep 关着）。
          </div>
        </div>
      ),
      onOk: () => {
        void runNow(ids);
      },
    });
  };

  const runAll = () => {
    const ids = allItems.map((item) => item.id);
    setSelected(new Set(ids));
    requestRun(ids);
  };

  const runFailed = () => {
    const ids = (report?.results ?? [])
      .filter((row) => row.status === "fail")
      .map((row) => row.id)
      .filter((id) => itemById.has(id));
    if (ids.length === 0) {
      message.info("上一轮没有失败项");
      return;
    }
    setSelected(new Set(ids));
    requestRun(ids);
  };

  const runMutating = () => {
    const ids = allItems.filter((item) => item.mutates).map((item) => item.id);
    if (ids.length === 0) {
      message.info("清单里没有写库类检查");
      return;
    }
    setSelected(new Set(ids));
    requestRun(ids);
  };

  const downloadJson = () => {
    if (!report) return;
    const payload = JSON.stringify(
      { exportedAt: new Date().toISOString(), params: activeParams, clientResults, report },
      null,
      2,
    );
    const blob = new Blob([payload], { type: "application/json;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `sekainook-selftest-${fileStamp()}.json`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
    message.success("JSON 报告已开始下载");
  };

  const copyMarkdown = async () => {
    if (!report) return;
    const markdown = buildMarkdown(report, activeParams, (id) => groupNameById.get(id) ?? id);
    const ok = await copyText(markdown);
    if (ok) message.success("Markdown 报告已复制");
    else message.error("复制失败：浏览器没给剪贴板权限，可以改用「导出 JSON」");
  };

  const webClientCount = (manifest?.clientChecks?.web ?? WEB_CLIENT_IDS).length;

  return (
    <>
      {modalContextHolder}

      <Card className={styles.infoCard} variant="borderless">
        <div className={styles.infoHeader}>
          <div className={styles.infoIcon}>
            <ExperimentOutlined />
          </div>
          <div className={styles.infoText}>
            <div className={styles.appName}>全站自检</div>
            <div className={styles.appDesc}>
              浏览器先跑 {webClientCount} 项本地检查，再让服务端把勾选的项跑一遍；结果按状态汇总，失败的排最前面。
              密码就用进门时那道，不用再输一次。
            </div>
          </div>
        </div>
        <div className={styles.versionRow}>
          <span className={styles.versionLabel}>清单</span>
          <span className={styles.versionTag}>
            {manifest ? `v${manifest.version} · ${manifest.groups.length} 组 / ${allItems.length} 项` : "还没拉到"}
          </span>
          <span className={styles.versionLabel}>生成于</span>
          <span className={styles.versionTag}>{manifest ? formatClock(manifest.generatedAt) : "—"}</span>
          <Button size="small" icon={<ReloadOutlined />} loading={loadingManifest} onClick={() => void loadManifest(true)}>
            重新拉取
          </Button>
        </div>
        {manifestError ? (
          <Alert
            type="error"
            showIcon
            style={{ marginTop: 12 }}
            message="清单没拉到"
            description={`${manifestError}（后端在 127.0.0.1:8788 上跑着吗？）`}
            action={
              <Button size="small" onClick={() => void loadManifest(true)}>
                重试
              </Button>
            }
          />
        ) : null}
      </Card>

      {manifest ? (
        <Space direction="vertical" size={12} style={{ width: "100%", marginTop: 12 }}>
          <Card className={styles.infoCard} variant="borderless">
            <div className={styles.infoHeader}>
              <div className={styles.infoIcon}>
                <ThunderboltOutlined />
              </div>
              <div className={styles.infoText}>
                <div className={styles.appName}>参数与预设</div>
                <div className={styles.appDesc}>
                  不带参数就全用后端默认值；预设一键把「勾哪些项 / 传哪些参数」摆好。
                </div>
              </div>
            </div>
            <Space size={[8, 8]} wrap>
              {manifest.presets.map((preset) => (
                <Tooltip key={preset.id} title={preset.desc}>
                  <Button size="small" onClick={() => applyPreset(preset)}>
                    {preset.name}
                  </Button>
                </Tooltip>
              ))}
            </Space>
            <div className={styles.pinHint} style={{ marginTop: 10 }}>
              这一次会带上的参数：{paramText}
            </div>
            <Collapse
              ghost
              style={{ marginTop: 8 }}
              activeKey={openParams}
              onChange={(keys) => setOpenParams(keys)}
              items={[
                {
                  key: "params",
                  label: (
                    <span style={{ display: "inline-flex", alignItems: "center", gap: 8, flexWrap: "wrap" }}>
                      <span className={styles.entryName} style={{ fontSize: 15 }}>
                        自定义参数
                      </span>
                      <Tag>{manifest.params.length} 个</Tag>
                      <span className={styles.entryDesc}>留空的项不会发出去，后端按自己的默认值算</span>
                    </span>
                  ),
                  children: (
                    <div>
                      <div
                        style={{
                          display: "grid",
                          gridTemplateColumns: "repeat(auto-fill, minmax(230px, 1fr))",
                          gap: 12,
                        }}
                      >
                        {manifest.params.map((def) => (
                          <div key={def.name} className={styles.nameField}>
                            <div className={styles.nameLabel}>
                              {def.label}
                              <span style={{ marginLeft: 6, color: "var(--color-text-tertiary)" }}>{def.name}</span>
                            </div>
                            <ParamControl def={def} value={params[def.name]} onChange={(value) => setParam(def.name, value)} />
                            {def.desc ? (
                              <div className={styles.pinHint} style={{ marginTop: 0 }}>
                                {def.desc}
                              </div>
                            ) : null}
                          </div>
                        ))}
                      </div>
                      <Button size="small" style={{ marginTop: 12 }} onClick={() => setParams(initParams(manifest.params))}>
                        恢复清单默认值
                      </Button>
                    </div>
                  ),
                },
              ]}
            />
          </Card>

          <Card className={styles.infoCard} variant="borderless">
            <div className={styles.infoHeader}>
              <div className={styles.infoIcon}>
                <SafetyCertificateOutlined />
              </div>
              <div className={styles.infoText}>
                <div className={styles.appName}>检查项</div>
                <div className={styles.appDesc}>
                  共 {allItems.length} 项 / {manifest.groups.length} 组；带「写库」的默认不勾，勾了跑之前还会再问一次。
                </div>
              </div>
            </div>
            <Space size={[8, 8]} wrap>
              <Button size="small" onClick={() => selectAll(true)}>
                全选
              </Button>
              <Button size="small" onClick={() => selectAll(false)}>
                全不选
              </Button>
              <Button
                size="small"
                onClick={() => setOpenGroups(openGroups.length > 0 ? [] : manifest.groups.map((group) => group.id))}
              >
                {openGroups.length > 0 ? "全部收起" : "全部展开"}
              </Button>
              <span className={styles.pinHint} style={{ marginTop: 0 }}>
                已选 {selectedItems.length} 项（其中写库 {mutatingSelected.length} 项）
              </span>
            </Space>
            <Collapse
              ghost
              style={{ marginTop: 8 }}
              activeKey={openGroups}
              onChange={(keys) => setOpenGroups(keys)}
              items={manifest.groups.map((group) => {
                const picked = group.items.filter((item) => selected.has(item.id)).length;
                return {
                  key: group.id,
                  label: (
                    <span
                      style={{ display: "flex", flexWrap: "wrap", alignItems: "center", gap: 8 }}
                      onClick={(event) => event.stopPropagation()}
                    >
                      <Checkbox
                        checked={picked === group.items.length && picked > 0}
                        indeterminate={picked > 0 && picked < group.items.length}
                        onChange={(event) => {
                          event.stopPropagation();
                          setGroupSelected(group, event.target.checked);
                        }}
                      />
                      <span className={styles.entryName}>{group.name}</span>
                      <Tag>
                        {picked}/{group.items.length}
                      </Tag>
                      {group.items.some((item) => item.client === "web") ? <Tag color="blue">含客户端自检</Tag> : null}
                      {group.items.some((item) => item.mutates) ? <Tag color="volcano">含写库</Tag> : null}
                      {group.desc ? <span className={styles.entryDesc}>{group.desc}</span> : null}
                    </span>
                  ),
                  children: (
                    <div className={styles.nameFields}>
                      {group.items.map((item) => (
                        <div key={item.id} className={styles.nameField}>
                          <Checkbox checked={selected.has(item.id)} onChange={(event) => toggleItem(item.id, event.target.checked)}>
                            <span style={{ display: "inline-flex", flexWrap: "wrap", alignItems: "center", gap: 6 }}>
                              <span className={styles.entryName} style={{ fontSize: 14 }}>
                                {item.name}
                              </span>
                              <span className={styles.entryDesc} style={{ marginTop: 0 }}>
                                {item.id}
                              </span>
                              {item.side === "client" ? <Tag color="blue">客户端自检</Tag> : null}
                              {item.client === "flutter" ? <Tag>Flutter</Tag> : null}
                              {item.mutates ? <Tag color="volcano">写库</Tag> : null}
                              {item.danger === "destructive" ? <Tag color="red">危险</Tag> : null}
                              <span className={styles.entryDesc} style={{ marginTop: 0 }}>
                                ~{item.estMs}ms
                              </span>
                            </span>
                          </Checkbox>
                          <div className={styles.entryDesc}>
                            {item.desc}
                            {item.params.length > 0 ? `（用到参数：${item.params.join("、")}）` : ""}
                          </div>
                        </div>
                      ))}
                    </div>
                  ),
                };
              })}
            />
          </Card>

          <Card className={styles.infoCard} variant="borderless">
            <div className={styles.infoHeader}>
              <div className={styles.infoIcon}>
                <PlayCircleOutlined />
              </div>
              <div className={styles.infoText}>
                <div className={styles.appName}>跑一遍</div>
                <div className={styles.appDesc}>
                  服务端那批是一次请求跑完再回，中途只能停止等待（结果不再回填）；本地那几项是真停。
                </div>
              </div>
            </div>
            <Space size={[8, 8]} wrap>
              <Button
                type="primary"
                icon={<PlayCircleOutlined />}
                loading={running}
                disabled={running || selectedItems.length === 0}
                onClick={() => requestRun(selectedItems.map((item) => item.id))}
              >
                运行选中的 {selectedItems.length} 项
              </Button>
              {running ? (
                <Button danger icon={<StopOutlined />} onClick={stopRun}>
                  停止
                </Button>
              ) : null}
              <Button icon={<ThunderboltOutlined />} disabled={running} onClick={runAll}>
                全部跑一遍
              </Button>
              <Button disabled={running || failedTotal === 0} onClick={runFailed}>
                只跑失败项{failedTotal > 0 ? `（${failedTotal}）` : ""}
              </Button>
              <Button disabled={running || mutatingTotal === 0} onClick={runMutating}>
                只跑写库项{mutatingTotal > 0 ? `（${mutatingTotal}）` : ""}
              </Button>
            </Space>
            {running ? (
              <div className={styles.scanResult} style={{ marginTop: 12, marginBottom: 0 }}>
                <Progress percent={phasePercent} status="active" showInfo={false} />
                <div className={styles.pinHint} style={{ marginTop: 6 }}>
                  {phaseText || "跑着…"} · 已等 {(elapsed / 1000).toFixed(1)}s
                </div>
              </div>
            ) : null}
            {stopped && !running ? (
              <div className={styles.pinHint} style={{ marginTop: 8 }}>
                上一轮停了：本地那几项没跑完，服务端那批的结果也没回填。
              </div>
            ) : null}
          </Card>

          {clientResults.length > 0 && !report ? (
            <Card className={styles.infoCard} variant="borderless">
              <div className={styles.appName} style={{ fontSize: 16 }}>
                客户端自检结果（服务端那批还没回）
              </div>
              <div className={styles.nameFields} style={{ marginTop: 8 }}>
                {clientResults.map((row) => (
                  <div key={row.id}>
                    <Tag color={STATUS_META[row.status].tag}>
                      {STATUS_META[row.status].mark} {row.id}
                    </Tag>
                    <span className={styles.entryDesc}>
                      {row.detail}（{row.ms ?? 0}ms）
                    </span>
                  </div>
                ))}
              </div>
            </Card>
          ) : null}

          {report ? (
            <Card className={styles.infoCard} variant="borderless">
              <div className={styles.infoHeader}>
                <div className={styles.infoIcon}>
                  <SafetyCertificateOutlined />
                </div>
                <div className={styles.infoText}>
                  <div className={styles.appName}>结果</div>
                  <div className={styles.appDesc}>
                    {formatClock(report.ranAt)} 跑完，用时 {report.durationMs}ms
                    {report.env?.origin ? ` · ${report.env.origin}` : ""}
                    {workerLabel(report.env?.worker) ? ` · Worker ${workerLabel(report.env?.worker)}` : ""}
                    {report.env?.db ? ` · DB ${report.env.db}` : ""}
                  </div>
                </div>
              </div>
              <Space size={[8, 8]} wrap>
                <Tag>共 {report.summary.total} 项</Tag>
                <Tag color="success">通过 {report.summary.passed}</Tag>
                <Tag color="error">失败 {report.summary.failed}</Tag>
                <Tag color="warning">留意 {report.summary.warned}</Tag>
                <Tag>跳过 {report.summary.skipped}</Tag>
                <Button size="small" icon={<DownloadOutlined />} onClick={downloadJson}>
                  导出 JSON
                </Button>
                <Button size="small" icon={<CopyOutlined />} onClick={() => void copyMarkdown()}>
                  复制 Markdown
                </Button>
              </Space>
              {report.clientMissing && report.clientMissing.length > 0 ? (
                <Alert
                  type="warning"
                  showIcon
                  style={{ marginTop: 12 }}
                  message={`服务端在等这些客户端结果：${report.clientMissing.join("、")}`}
                />
              ) : null}
              {report.notes && report.notes.length > 0 ? (
                <Alert type="info" showIcon style={{ marginTop: 12 }} message={report.notes.join(" / ")} />
              ) : null}
              <Collapse
                key={report.ranAt}
                ghost
                style={{ marginTop: 8 }}
                defaultActiveKey={orderedResults
                  .filter((row) => row.status === "fail")
                  .map((row) => `${row.id}`)}
                items={orderedResults.map((row) => {
                  const meta = STATUS_META[row.status];
                  return {
                    key: row.id,
                    label: (
                      <span style={{ display: "inline-flex", flexWrap: "wrap", alignItems: "center", gap: 8 }}>
                        <Tag color={meta.tag} icon={meta.icon}>
                          {meta.label}
                        </Tag>
                        <span className={styles.entryName} style={{ fontSize: 14 }}>
                          {row.name || row.id}
                        </span>
                        <span className={styles.entryDesc} style={{ marginTop: 0 }}>
                          {row.id}
                        </span>
                        {row.group ? <Tag>{groupNameById.get(row.group) ?? row.group}</Tag> : null}
                        {row.side === "client" ? <Tag color="blue">客户端自检</Tag> : null}
                        <span className={styles.entryDesc} style={{ marginTop: 0 }}>
                          {row.ms ?? 0}ms
                        </span>
                      </span>
                    ),
                    children: (
                      <div>
                        <div className={styles.entryDesc} style={{ marginTop: 0 }}>
                          {row.detail || "（没有详情）"}
                        </div>
                        {row.hint ? <div className={styles.pinHint}>提示：{row.hint}</div> : null}
                        {row.data !== undefined && row.data !== null ? (
                          <pre
                            style={{
                              margin: "8px 0 0",
                              padding: "10px 12px",
                              borderRadius: 10,
                              background: "var(--color-surface-soft)",
                              fontSize: 12,
                              lineHeight: 1.6,
                              maxHeight: 260,
                              overflow: "auto",
                              whiteSpace: "pre-wrap",
                              wordBreak: "break-all",
                            }}
                          >
                            {JSON.stringify(row.data, null, 2)}
                          </pre>
                        ) : null}
                      </div>
                    ),
                  };
                })}
              />
            </Card>
          ) : null}
        </Space>
      ) : null}
    </>
  );
}
