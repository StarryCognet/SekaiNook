# 手机视口验证工具（Flutter Web）

Flutter Web 在浏览器里渲染到 canvas，DOM 里没有文本，`resizeTo` 也改不了视口
（只改 `outerWidth`，`innerWidth` 不变），所以「手机形态」只能靠**固定尺寸的 iframe**：
iframe 有自己的 `window.innerWidth`，Flutter 会按它布局。

## 用法

```bash
# 1) 本地后端（复用线上数据副本）
cd E:/Git/SekaiNook && npx wrangler pages dev public --port 8788

# 2) 构建 Flutter Web —— 必须带 API_BASE，否则会去连线上、本机无外网时全是空态
cd E:/Git/SekaiNook-App
flutter build web --release --no-pub --dart-define=API_BASE=http://127.0.0.1:8788

# 3) 静态托管 + 取景框（build/web 会被下一次 build 清掉，所以每次重新拷）
cp tool/webharness/harness.html build/web/harness.html
cp tool/webharness/diag.sh build/web/diag.sh
cd build/web && python -m http.server 5000

# 4) 用 CDP 代理开取景框页，拿到 targetId
curl -s -X POST http://localhost:3456/new -d "http://127.0.0.1:5000/harness.html"
# → {"targetId":"..."}

# 5) 逐角色/主题/页面截图
bash build/web/diag.sh <targetId>     # 输出到 docs/shots/diag/*.png

# 6) 启动动画验证：1s 应看到 🌱 启动动画、3s 应已撤掉露出页面
bash build/web/boot.sh <targetId>
```

## 为什么不是直接开 App 页

CDP 代理没有视口控制接口（`Emulation.setDeviceMetricsOverride` 拿不到目标），
而 iframe 方案还顺带解决了另一个问题：**同源**，所以能用 `/eval` 直接改 iframe 的
`localStorage`（`flutter.sekainook_role` / `flutter.sekainook_theme`）再 reload，
一键切「妹妹版 / 妈妈版 × 浅色 / 深色」。

## 注意

- 后台标签页截图会返回旧帧 —— 切页面前后用 `/new` 开新标签，或用 `diag.sh` 里的
  「改 hash + reload + sleep 9」流程。
- SharedPreferences 落 localStorage 时键名带 `flutter.` 前缀，值是按 JSON 编码的
  （所以 `localStorage.setItem('flutter.sekainook_role','"parent"')` 要带引号）。
