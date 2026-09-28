import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    open: true,
    // 本地联调：把 /api 请求转发给 wrangler pages dev（Pages Functions + 本地 D1）
    proxy: {
      '/api': {
        // 用 127.0.0.1 而非 localhost：Node 可能把 localhost 解析到 IPv6 ::1，
        // 而 wrangler/workerd 只监听 IPv4，会导致代理连接被拒（表现为 500/502）
        target: 'http://127.0.0.1:8788',
        changeOrigin: true,
      },
    },
  },
});
