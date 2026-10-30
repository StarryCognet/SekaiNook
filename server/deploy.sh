#!/bin/sh
# 服务器部署脚本 —— 由 /opt/sekainook.git/hooks/post-receive 调用
#
# 用法：
#   deploy.sh <old-rev> <new-rev>
#
# 做什么：
#   1. server/package.json 有变化 → 重装后端依赖
#   2. app/ src/ public/ 有变化 → 服务器自己构建 Flutter Web 并更新 web/
#   3. 重启后端服务
#
# 只做增量判断，没改的部分不重复折腾。

set -e

OLD="${1:-}"
NEW="${2:-}"

ROOT=/opt/sekainook
GIT="git --git-dir=${ROOT}.git --work-tree=${ROOT}"

# Flutter 走国内镜像（首次 flutter 命令会用到）
FLUTTER_BIN=/opt/flutter-sdk/flutter/bin
export PATH="${FLUTTER_BIN}:${PATH}"
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

cd "${ROOT}"

# 判断某类路径是否在本次推送中变化；参数是 grep -E 的正则
changed() {
  [ -n "${OLD}" ] && [ -n "${NEW}" ] &&
    ${GIT} diff --name-only "${OLD}" "${NEW}" 2>/dev/null | grep -qE "$1"
}

# 1) 后端依赖
if changed '^server/package\.json$'; then
  echo "[deploy] server/package.json 有变化 → 重装后端依赖"
  (cd "${ROOT}/server" && npm i --silent)
fi

# 2) 前端构建
if [ -z "${OLD}" ] || [ -z "${NEW}" ] || changed '^(app/|src/|public/)'; then
  echo "[deploy] 前端源码有变化 → 构建 Flutter Web（约 1~2 分钟）"
  cd "${ROOT}/app"
  if [ ! -d .dart_tool ]; then
    echo "[deploy] 首次构建，先 flutter pub get"
    flutter pub get
  fi
  flutter build web --release --no-pub \
    --dart-define=API_BASE=http://140.143.240.238
  cd "${ROOT}"
  rm -rf web
  cp -r app/build/web web
  echo "[deploy] 前端已更新到 ${ROOT}/web"
else
  echo "[deploy] 前端源码无变化，跳过构建"
fi

# 3) 重启后端（sudoers 里已为 ubuntu 开免密）
sudo -n /usr/bin/systemctl restart sekainook
echo "[deploy] 后端已重启"
