import { lazy, Suspense } from "react";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { ConfigProvider } from "antd";
import zhCN from "antd/locale/zh_CN";
import MainLayout from "./layouts/MainLayout";
import RoleGate from "./components/RoleGate";
import { PageLoading } from "./components/StateViews";
import { useFamilyStore } from "./store/useFamilyStore";
import { antdTheme } from "./theme/tokens";

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

/** 应用根组件 */
export default function App() {
  return (
    <ConfigProvider locale={zhCN} theme={antdTheme}>
      <BrowserRouter>
        <AppRoutes />
      </BrowserRouter>
    </ConfigProvider>
  );
}
