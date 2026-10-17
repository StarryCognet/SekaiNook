#!/usr/bin/env bash
# 启动动画验证：reload 后在 1s / 3s 各抓一帧 —— 1s 应看到 HTML 启动动画（🌱 + 进度条），
# 3s 应该已经撤掉、露出真正的页面（说明 Dart 首帧回调生效，没等到 8 秒兜底）。
# 用法：bash boot.sh <targetId>
set -u
T="${1:?usage: boot.sh <targetId>}"
OUT="E:/Git/SekaiNook-App/docs/shots/diag"
mkdir -p "$OUT"
curl -s -X POST "http://localhost:3456/eval?target=$T" -d "(function(){var f=document.getElementById('a').contentWindow;f.localStorage.setItem('flutter.sekainook_role','\"child\"');f.location.hash='#/home';f.location.reload();return 'ok'})()" >/dev/null
sleep 1
curl -s "http://localhost:3456/screenshot?target=$T&file=$OUT/boot-1s.png" >/dev/null; echo shot boot-1s
sleep 2
curl -s "http://localhost:3456/screenshot?target=$T&file=$OUT/boot-3s.png" >/dev/null; echo shot boot-3s
