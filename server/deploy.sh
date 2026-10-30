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

# git 在 post-receive 钩子里会导出 GIT_DIR / GIT_WORK_TREE 等变量。
# 子进程（flutter / dart / git）继承这些变量后，会把它们当成「当前仓库」，
# 于是 Flutter 的版本检查在 app/ 目录跑 git log 时报
#   fatal: not a git repository: '.'
# 这里清掉，让子进程按正常方式自己找 .git。
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX

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
# 除了前端源码，构建配置本身（deploy.sh / 根 package.json）变了也要重建 ——
# 否则改完构建参数（比如 --no-web-resources-cdn）推送上去，前端产物还是旧的。
if [ -z "${OLD}" ] || [ -z "${NEW}" ] || changed '^(app/|src/|public/|server/deploy\.sh$|package\.json$)'; then
  echo "[deploy] 前端源码有变化 → 构建 Flutter Web（约 1~2 分钟）"
  cd "${ROOT}/app"
  if [ ! -d .dart_tool ]; then
    echo "[deploy] 首次构建，先 flutter pub get"
    flutter pub get
  fi
  # --no-wasm-dry-run 跳过 wasm 兼容性试编译，省 10~20 秒
  # --no-web-resources-cdn：canvaskit 改为从本站 canvaskit/ 加载。
  #   不加这个开关时 Flutter 会去 www.gstatic.com 拉 canvaskit.js + canvaskit.wasm（7.3MB），
  #   国内基本拉不动 —— 页面会长时间白屏/“卡死”，刷新也一样。这是测试站卡顿的头号嫌疑。
  flutter build web --release --no-pub --no-wasm-dry-run --no-web-resources-cdn \
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
