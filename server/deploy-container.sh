#!/bin/sh
# 容器化部署脚本 —— 由 /opt/sekainook/git-repo/sekainook.git/hooks/post-receive 调用
#
# 用法：deploy-container.sh <old-rev> <new-rev>
#
# 和老版本 server/deploy.sh 的区别（那套是"裸装 systemd"时代的，已废弃）：
#   - 后端不再是宿主机 node 进程，而是 Docker 镜像 → 代码变了要「重建镜像」而不是 npm i
#   - 前端不再在服务器构建（服务器没有 Flutter SDK，且曾因增量缓存产出坏产物）
#     → app/ 变了必须在本机跑 server/deploy-web.ps1 上传产物，这里只提示
#   - 重启用 docker compose，不是 systemctl
#
# ⚠️ 所有 echo 一律英文：这个脚本的输出会经 `git push` 回显到 Windows 的
#    PowerShell 控制台（GBK），中文会变乱码，所以终端文案不写中文。
#
# 只做增量判断，没改的部分不重复折腾。

set -e

# git 在 post-receive 钩子里会导出 GIT_DIR / GIT_WORK_TREE，
# 子进程（docker 里的 git 操作等）继承后可能把「当前仓库」认错，清掉更安全。
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX

OLD="${1:-}"
NEW="${2:-}"

ROOT=/opt/sekainook
GIT_DIR_PATH="${ROOT}/git-repo/sekainook.git"
COMPOSE_FILE="${ROOT}/deploy/docker/sekainook.compose.yml"
DC="docker compose -f ${COMPOSE_FILE}"

cd "${ROOT}"

# 判断某类路径是否在本次推送中变化；参数是 grep -E 的正则
changed() {
  [ -n "${OLD}" ] && [ -n "${NEW}" ] &&
    git --git-dir="${GIT_DIR_PATH}" diff --name-only "${OLD}" "${NEW}" 2>/dev/null | grep -qE "$1"
}

# ---------- 1) 后端：代码/依赖/Dockerfile 变了 → 重建镜像并重启 ----------
# 注意 server/ 整个目录：package.json（依赖）、index.ts / env.ts 等（代码）都在里面，
# 而且代码是 COPY 进镜像的（不是挂载），所以任何一处变了都得重建。
if changed '^(server/|functions/|migrations/|deploy/docker/Dockerfile$)'; then
  echo "[deploy] backend code changed -> rebuilding image (30-60s)"
  ${DC} up -d --build backend
else
  echo "[deploy] backend unchanged, skip"
fi

# ---------- 2) 前端：只提示，不处理 ----------
# app/ 的产物不在 git 里（服务器不装 Flutter），必须在 Windows 本机构建后上传。
if changed '^app/'; then
  echo ""
  echo "[deploy] WARNING: app/ changed, but the web build must be produced locally:"
  echo "         cd E:\\Git\\SekaiNook"
  echo "         .\\server\\deploy-web.ps1"
  echo "         (the server has no Flutter SDK, so it cannot build this itself)"
  echo ""
fi

# ---------- 3) nginx 配置变了 → 先 -t 校验再 reload ----------
if changed '^deploy/nginx/web-container\.conf$'; then
  echo "[deploy] nginx config changed -> validating and reloading"
  if docker exec sekainook-web nginx -t; then
    docker exec sekainook-web nginx -s reload
    echo "[deploy] nginx reloaded"
  else
    echo "[deploy] ERROR: nginx config test failed, kept the old config running (not reloaded)" >&2
    echo "[deploy]        fix it, then: docker exec sekainook-web nginx -t && docker exec sekainook-web nginx -s reload" >&2
  fi
fi

# ---------- 4) compose 本身变了 → 重新 up（会按需重建/重建容器） ----------
if changed '^deploy/docker/sekainook\.compose\.yml$'; then
  echo "[deploy] compose file changed -> up -d"
  ${DC} up -d
fi

# ---------- 5) 备份脚本变了 → 什么都不用做（cron 直接读文件） ----------
if changed '^server/backup\.sh$'; then
  echo "[deploy] backup script changed -> nothing to do (cron reads it on each run)"
fi

# ---------- 6) 版本日志：改了 src/config/changelog.ts → 灌进运行时 SQLite ----------
# 网页版和 App 都从 GET /api/changelog 读，而它读的是数据库（不是 bundle 里那层兜底）。
# 不写库的话，新版本在「设置 → 版本日志」里看不到，只有接口挂掉才退回 bundle。
#
# 为什么在容器里跑：宿主机没装 node（后端也进了容器），而镜像里既有 node 又有 tsx，
# 能直接 import .ts 生成 SQL；镜像里没有 sqlite3 CLI，所以执行 SQL 也借容器的 better-sqlite3。
# 生成失败只告警不中断 —— 版本日志不该卡住部署。
if changed '^src/config/changelog\.ts$|^scripts/changelog-sync\.mjs$'; then
  echo "[deploy] changelog changed -> syncing into container SQLite"
  if docker exec sekainook-backend node scripts/changelog-sync.mjs sync --dry >/dev/null 2>&1; then
    docker exec sekainook-backend node -e '
      const fs = require("node:fs");
      const Database = require("/app/server/node_modules/better-sqlite3");
      const db = new Database("/app/data/sekainook.db");
      db.exec(fs.readFileSync("/app/migrations/.changelog-sync.sql", "utf8"));
      const n = db.prepare("SELECT COUNT(*) AS n FROM changelog").get().n;
      console.log("[deploy] changelog rows = " + n);
      db.close();
    '
  else
    echo "[deploy] WARNING: could not generate changelog SQL in container, skipped" >&2
  fi
fi

echo "[deploy] done -> http://140.143.240.238/sekainook/"
