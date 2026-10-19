#!/usr/bin/env bash
# 诊断抓图：手机视口（390×844 iframe）下逐角色/主题/页面截图。
# 用法：bash diag.sh <targetId>
set -u
T="${1:?usage: diag.sh <targetId>}"
OUT="E:/Git/SekaiNook-App/docs/shots/diag"
mkdir -p "$OUT"

shot() { # $1 role  $2 theme  $3 hash  $4 file
  curl -s -X POST "http://localhost:3456/eval?target=$T" -d "(function(){var f=document.getElementById('a').contentWindow;f.localStorage.setItem('flutter.sekainook_role','\"$1\"');f.localStorage.setItem('flutter.sekainook_theme','\"$2\"');f.location.hash='$3';f.location.reload();return 'ok'})()" >/dev/null
  sleep 9
  curl -s "http://localhost:3456/screenshot?target=$T&file=$OUT/$4" >/dev/null
  echo "shot $4"
}

shot parent original '#/home'     parent-light.png
shot child  original '#/home'     kid-light.png
shot parent original '#/family'   family-light.png
shot child  original '#/garden'   garden-light.png
shot parent original '#/settings' settings-light.png
shot parent midnight '#/home'     parent-dark.png
shot child  midnight '#/garden'   garden-dark.png
shot parent midnight '#/home/notifications' notif-dark.png
