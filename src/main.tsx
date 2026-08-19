import React from 'react';
import ReactDOM from 'react-dom/client';
import { App as AntApp } from 'antd';
import dayjs from 'dayjs';
import 'dayjs/locale/zh-cn';
import App from './App';
import './theme/global.css';

dayjs.locale('zh-cn');

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    {/* AntApp 提供 message/notification 上下文 */}
    <AntApp>
      <App />
    </AntApp>
  </React.StrictMode>
);