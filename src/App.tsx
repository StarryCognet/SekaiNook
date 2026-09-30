import { lazy, Suspense, useEffect, useMemo } from "react";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { ConfigProvider } from "antd";
import zhCN from "antd/locale/zh_CN";
import MainLayout from "./layouts/MainLayout";
import RoleGate from "./components/RoleGate";
import ErrorBoundary from "./components/ErrorBoundary";
import { PageLoading } from "./components/StateViews";
import { useFamilyStore } from "./store/useFamilyStore";
import { useThemeStore } from "./store/useThemeStore";
import { buildAntdTheme, themePreset } from "./theme/themes";

/**
 * 路由级页面按需加载：首屏只保留应用壳（主题 + 路由 + 身份门 + 主布局）。
 * 与静态 import 的组件、默认导出、path 完全一致，只改变加载时机。
 */
const HomePage = lazy(() => import("./views/home/HomePage"));
const NotificationsPage = lazy(() => import("./views/home/NotificationsPage"));
const FamilyDashboard = lazy(() => import("./views/family/FamilyDashboard"));
const WeeklyPlan = lazy(() => import("./views/family/WeeklyPlan"));
const GardenLayout = lazy(() => import("./layouts/GardenLayout"));
const SettingsPage = lazy(() => import("./views/settings/SettingsPage"));

/** 根路由：跳首页（首页内部再按身份分成妹妹版 / 妈妈版） */
function HomeRedirect() {
  return <Navigate to="/home" replace />;
}

/**
 * 路由表。
 * 未选择身份时（新设备首次打开）先过身份选择门，不再默认进家长模式。
 */
function AppRoutes() {
  const role = useFamilyStore((s) => s.role);
  if (!role) return <RoleGate />;

  return (
    <Suspense fallback={<PageLoading />}>
      <Routes>
        <Route path="/" element={<HomeRedirect />} />
        <Route element={<MainLayout />}>
          <Route path="/home" element={<HomePage />} />
          <Route path="/home/notifications" element={<NotificationsPage />} />
          <Route path="/family" element={<FamilyDashboard />} />
          <Route path="/family/plan" element={<WeeklyPlan />} />
          <Route path="/garden" element={<GardenLayout />} />
          <Route path="/settings" element={<SettingsPage />} />
        </Route>
        <Route path="*" element={<Navigate to="/home" replace />} />
      </Routes>
    </Suspense>
  );
}

/**
 * 首屏防闪的「背景图影子缓存」键：背景图存在服务端，刷新时首帧拿不到，
 * 所以每台设备拿到后往本机存一份地址，交给 index.html 里那段内联脚本先铺上。
 * 只存服务端返回的稳定地址（/api/images/xxx），键名与 index.html 里保持一致。
 */
const BG_CACHE_KEY = "sekainook_bg_cache_v1";

/**
 * 应用根组件。
 * 全局外观（主题 + 背景图）在这里落地：
 *   - 主题：<html data-theme="..."> 换一组 CSS 变量（见 theme/global.css），
 *     antd 组件跟着换算法（buildAntdTheme）；
 *   - 背景图：把地址写进 --app-bg-image，并打上 data-bg="on"，
 *     底色与卡片据此变半透明，让照片透出来。
 * 主题存本机（每台设备各选各的），背景图存服务端（两台设备一致）。
 *
 * 这里写的属性名 / 底色必须和 index.html 里的内联防闪脚本一致，
 * 否则水合后会跳一下色（那边先画，这边随后纠正）。
 */
export default function App() {
  const themeId = useThemeStore((s) => s.themeId);
  const background = useThemeStore((s) => s.background);
  const backgroundReady = useThemeStore((s) => s.backgroundReady);
  const loadBackground = useThemeStore((s) => s.loadBackground);
  const hasBackground = background !== "";

  // 打开 App 时问一次服务端要背景图（读不到就当没设）
  useEffect(() => {
    void loadBackground();
  }, [loadBackground]);

  useEffect(() => {
    const root = document.documentElement;
    const preset = themePreset(themeId);
    root.dataset.theme = themeId;
    root.dataset.bg = hasBackground ? "on" : "off";
    root.style.setProperty("--app-bg-image", hasBackground ? `url("${background}")` : "none");
    // 内联底色：index.html 的防闪脚本在第一帧就把它写进 style，
    // 换主题时必须一起更新，否则内联样式会一直压着新主题的 --app-bg-base。
    root.style.backgroundColor = preset.palette.bg;

    // 手机浏览器地址栏 / 状态栏跟着主题变色（取该主题的页面底色）
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute("content", preset.palette.bg);

    // 首屏防闪用：影子存一份背景图地址（见 index.html 内联脚本）。
    // 等服务端的值真的到位（backgroundReady）再动缓存 —— 否则首帧那个空字符串
    // 会把上一份缓存抹掉，下次刷新就又只剩纯色。
    if (backgroundReady) {
      try {
        if (hasBackground) localStorage.setItem(BG_CACHE_KEY, background);
        else localStorage.removeItem(BG_CACHE_KEY);
      } catch {
        // 隐私模式：存不住只影响下次首屏，不影响功能
      }
    }
  }, [themeId, background, hasBackground, backgroundReady]);

  const themeConfig = useMemo(() => buildAntdTheme(themeId, hasBackground), [themeId, hasBackground]);

  return (
    // 最外层错误边界：渲染期异常（含懒加载 chunk 404）不再白屏，见 components/ErrorBoundary
    <ErrorBoundary>
      <ConfigProvider locale={zhCN} theme={themeConfig}>
        <BrowserRouter>
          <AppRoutes />
        </BrowserRouter>
      </ConfigProvider>
    </ErrorBoundary>
  );
}
