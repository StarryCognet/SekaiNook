# ===================================================================
# SekaiNook 后端镜像
#
# 构建（在代码根目录）：
#   docker build -f deploy/docker/Dockerfile -t sekainook-backend:latest .
#
# 也可以在 1Panel「容器 → 编排」里让它自动构建（见 sekainook.compose.yml，
# 里面用 context: /opt/sekainook + dockerfile: deploy/docker/Dockerfile）。
#
# ⚠️ 国内网络：Debian 官方源与 npm 官方 registry 在这台机器上会卡死。
#   实测 2026-10-31：deb.debian.org 的单个 Release 文件 12 秒超时，
#   第一版 Dockerfile 直接卡在 apt-get update 6 分钟没有任何进展。
#   所以 Debian 源换腾讯云（0.2s）、npm 换 npmmirror（0.09s）、
#   better-sqlite3 跳过 GitHub prebuild 直接本地编译。
#
# 为什么分成两层 COPY：
#   functions/ 是业务代码，改得很勤；server/package.json 很少变。
#   先装依赖再拷代码，改一行业务代码不会触发 npm install 重跑。
#
# 运行时：cwd = /app，server/index.ts 用 process.cwd() 去找
#   /app/functions（路由来源）和 /app/data（SQLite + 图片）
# ===================================================================

FROM node:22-bookworm-slim

# better-sqlite3 是原生模块，编译工具链必须备着
# （没有它会在 npm install 阶段报 node-gyp 失败）
#
# 注意 bookworm-slim 现在用 deb822 格式的 /etc/apt/sources.list.d/debian.sources，
# 没有 /etc/apt/sources.list —— 两种都兼容一下，否则 sed 直接报文件不存在。
RUN set -eux; \
    for f in /etc/apt/sources.list.d/debian.sources /etc/apt/sources.list; do \
        if [ -f "$f" ]; then \
            sed -i 's|deb.debian.org|mirrors.cloud.tencent.com|g; s|security.debian.org|mirrors.cloud.tencent.com|g' "$f"; \
        fi; \
    done; \
    apt-get update; \
    apt-get install -y --no-install-recommends python3 make g++; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# ① 依赖层（缓存友好）
COPY server/package.json ./server/

# better-sqlite3 默认会先去 GitHub 下 prebuild（国内超时几十秒后才回退编译），
# 这里直接强制本地编译，node-gyp 的 headers 也从 npmmirror 取。
ENV npm_config_registry=https://registry.npmmirror.com \
    npm_config_disturl=https://npmmirror.com/mirrors/node \
    npm_config_build_from_source=true

RUN cd server \
 && npm install --omit=dev \
 && npm cache clean --force

# ② 业务代码层
# .dockerignore 已排除 **/node_modules，所以这里不会覆盖掉上一步装好的依赖
COPY functions ./functions
COPY server ./server

# 迁移脚本（容器里手工应用：docker exec -it sekainook-backend sqlite3 ...）
COPY migrations ./migrations

# 版本日志的播种源 + 生成脚本。
# 网页版和 App 都从 GET /api/changelog 读，而它读的是运行时 SQLite（不是 bundle 里那份），
# 所以每次改 src/config/changelog.ts 都得把它写进库。宿主机没有 node，
# 但镜像里既有 node 又有 tsx（能直接 import .ts），让部署脚本在容器里跑最省事。
COPY src/config/changelog.ts ./src/config/
COPY scripts/changelog-sync.mjs ./scripts/

# 数据目录占位，实际会被 compose 的 volume 覆盖
RUN mkdir -p /app/data

ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=8788

EXPOSE 8788

# 健康检查：镜像里没有 curl，用 node 自带 fetch。
# status < 500 视为存活（/api/ledger/summary 若需要鉴权，401 也算活着）
HEALTHCHECK --interval=30s --timeout=5s --start-period=25s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8788/api/ledger/summary').then(r=>process.exit(r.status<500?0:1)).catch(()=>process.exit(1))"

CMD ["node", "server/node_modules/tsx/dist/cli.mjs", "server/index.ts"]
