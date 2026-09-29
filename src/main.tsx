import React from 'react';
import ReactDOM from 'react-dom/client';
import { App as AntApp } from 'antd';
import dayjs from 'dayjs';
import 'dayjs/locale/zh-cn';
import App from './App';
import './theme/global.css';

dayjs.locale('zh-cn');

// PWA：仅在生产环境注册 Service Worker（提供「添加到主屏幕」与离线外壳）。
// 开发模式下绝不注册——Service Worker 会拦截请求并缓存，破坏 Vite 的 HMR。
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch(() => undefined);
  });
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    {/* AntApp 提供 message/notification 上下文 */}
    <AntApp>
      <App />
    </AntApp>
  </React.StrictMode>
);