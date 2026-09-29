import React from 'react';
import ReactDOM from 'react-dom/client';
import { App as AntApp } from 'antd';
import dayjs from 'dayjs';
import 'dayjs/locale/zh-cn';
import App from './App';
import './theme/global.css';
import { registerServiceWorker } from './utils/swUpdate';

dayjs.locale('zh-cn');

// PWA：仅在生产环境注册 Service Worker（提供「添加到主屏幕」与离线外壳）。
// 开发模式下绝不注册——Service Worker 会拦截请求并缓存，破坏 Vite 的 HMR。
// 注册与「有新版本」提示都在 src/utils/swUpdate.ts 里（脚本 URL 带构建标识）。
if (import.meta.env.PROD) {
  registerServiceWorker();
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    {/* AntApp 提供 message/notification 上下文 */}
    <AntApp>
      <App />
    </AntApp>
  </React.StrictMode>
);