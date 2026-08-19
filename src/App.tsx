import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { ConfigProvider } from "antd";
import zhCN from "antd/locale/zh_CN";
import MainLayout from "./layouts/MainLayout";
import FamilyDashboard from "./views/family/FamilyDashboard";
import WeeklyPlan from "./views/family/WeeklyPlan";
import GardenLayout from "./layouts/GardenLayout";
import SettingsPage from "./views/settings/SettingsPage";
import { antdTheme } from "./theme/tokens";

/** 根路由：跳转 /family（PC 显示仪表盘，移动端显示移动工作台） */
function HomeRedirect() {
  return <Navigate to="/family" replace />;
}

/** 应用根组件 */
export default function App() {
  return (
    <ConfigProvider locale={zhCN} theme={antdTheme}>
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<HomeRedirect />} />
          <Route element={<MainLayout />}>
            <Route path="/family" element={<FamilyDashboard />} />
            <Route path="/family/plan" element={<WeeklyPlan />} />
            <Route path="/garden" element={<GardenLayout />} />
            <Route path="/settings" element={<SettingsPage />} />
          </Route>
          <Route path="*" element={<Navigate to="/family" replace />} />
        </Routes>
      </BrowserRouter>
    </ConfigProvider>
  );
}
