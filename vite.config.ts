import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    open: true,
    // 监听所有网卡：安卓真机可用 http://<电脑局域网IP>:5173 联调
    // （API 请求仍由下面的代理转发到本机 8788，无需对外暴露 wrangler）
    host: true,
    watch: {
      // 编辑器的原子写入会在源码目录留下 .xxx.tmpdir/.xxx.tmp 临时文件，
      // chokidar 监听它可能抛 EBUSY 直接把整个 dev server 搞崩（本地实测），这里忽略掉
      ignored: ['**/.*.tmpdir/**', '**/.*.tmp'],
    },
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
  build: {
    /**
     * antd-vendor 是刻意整包隔离的厂商 chunk（约 855 kB / gzip 约 276 kB）：
     * 它的体积由 antd 决定，不是应用代码膨胀的信号。阈值抬到 900 是为了
     * ① 不再对这一个已知 chunk 反复告警；② 仍能拦住应用自身 chunk 的异常增长
     * （当前应用代码最大的 chunk 只有约 15 kB）。
     */
    chunkSizeWarningLimit: 900,
    rollupOptions: {
      output: {
        /**
         * 厂商代码按家族拆包：react 家族（含 scheduler）、antd 家族（含 rc-* 与 dayjs）、
         * echarts 家族（含 zrender）。echarts 只被懒加载的页面用到，拆出来后不会进首屏；
         * react / antd 家族从主 chunk 移出，便于浏览器长缓存。
         */
        manualChunks(id: string) {
          if (!id.includes('node_modules')) return;
          const nm = id.replace(/\\/g, '/');
          if (/\/node_modules\/(react|react-dom|react-router|react-router-dom|scheduler)\//.test(nm)) {
            return 'react-vendor';
          }
          if (/\/node_modules\/(antd|@ant-design|rc-[^/]+|dayjs)\//.test(nm)) {
            return 'antd-vendor';
          }
          if (/\/node_modules\/(echarts|echarts-for-react|zrender)\//.test(nm)) {
            return 'echarts-vendor';
          }
          return;
        },
      },
    },
  },
});
