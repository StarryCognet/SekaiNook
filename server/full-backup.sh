#!/usr/bin/env bash
# ============================================================
# SekaiNook full machine snapshot
#
# vs server/backup.sh:
#   backup.sh      runs daily at 03:00, business data only (db + images)
#   this script    run before a reinstall / migration; packs data + config
#                  + deployment chain into one archive, so the whole machine
#                  can be rebuilt elsewhere
#
# Contents:
#   data/sekainook.db     SQLite hot backup (sqlite3 .backup; WAL-safe, no lock)
#   data/r2/              image directory
#   .env                  env vars (CONTAINS ADMIN_PASSWORD, keep it secret)
#   etc/                  nginx / systemd / sudoers / cron (renamed explicitly
#                         to avoid same-basename collisions)
#   git-hooks/            post-receive deploy hook (a clone never carries it)
#   git-repo/sekainook.git bare repo with full history
#   web/                  Flutter Web build output
#   META.txt              row counts, file counts, HEAD, host
#   RESTORE.md            restore instructions
#
# Not included (rebuildable): node_modules, Flutter SDK, apt packages
#
# Usage:
#   sudo bash /opt/sekainook/server/full-backup.sh            # -> /tmp
#   sudo bash /opt/sekainook/server/full-backup.sh /root/bk   # custom dir
#
# NOTE: keep all *terminal* output ASCII. It is read from a Windows
# PowerShell console whose codepage is GBK, so UTF-8 Chinese shows up as
# mojibake. RESTORE.md is Chinese on purpose (a file, opened locally).
# ============================================================
set -euo pipefail

ROOT=/opt/sekainook
BARE=/opt/sekainook.git
OUT=${1:-/tmp}
TS=$(date +%Y%m%d-%H%M%S)
NAME="sekainook-full-${TS}.tar.gz"
STAGE=$(mktemp -d /tmp/snapshot.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT

say() { printf '[snapshot] %s\n' "$*"; }

# Copy only if the source exists; destination name is given explicitly so
# that same-basename files from different directories never overwrite.
copy_as() {
  local src=$1 dst=$2
  if [ -f "$src" ]; then
    cp -a "$src" "$STAGE/$dst"
    say "  $dst  <-  $src"
  fi
}

[ "$(id -u)" -eq 0 ] || { echo "ERROR: run with sudo (needs to read /etc)" >&2; exit 1; }
mkdir -p "$OUT" "$STAGE"/{data,etc,git-hooks,git-repo,web}

# ---------- 1. business data ----------
say "SQLite hot backup (.backup, WAL-safe)"
sqlite3 "$ROOT/data/sekainook.db" ".backup '$STAGE/data/sekainook.db'"

if [ -d "$ROOT/data/r2" ]; then
  say "r2/ image directory ($(find "$ROOT/data/r2" -type f 2>/dev/null | wc -l) files)"
  cp -a "$ROOT/data/r2" "$STAGE/data/"
fi

if [ -f "$ROOT/.env" ]; then
  say ".env (contains ADMIN_PASSWORD)"
  cp -a "$ROOT/.env" "$STAGE/.env"
fi

# ---------- 2. system config (hardest to rebuild) ----------
say "system config"
copy_as /etc/nginx/sites-available/sekainook nginx-sekainook.conf
copy_as /etc/nginx/nginx.conf                nginx.conf
copy_as /etc/systemd/system/sekainook.service sekainook.service
copy_as /etc/sudoers.d/sekainook              sudoers-sekainook
copy_as /etc/cron.d/sekainook-backup          cron-sekainook-backup

# Basic Auth file (name varies, so glob; body never runs if nothing matches)
for f in /etc/nginx/.htpasswd*; do
  if [ -f "$f" ]; then
    cp -a "$f" "$STAGE/etc/"
    say "  etc/$(basename "$f")"
  fi
done

# ---------- 3. deployment chain ----------
copy_as "$BARE/hooks/post-receive" "git-hooks/post-receive"

if [ -d "$BARE" ]; then
  say "bare repo /opt/sekainook.git (all objects + history)"
  cp -a "$BARE" "$STAGE/git-repo/"
fi

# ---------- 4. frontend output ----------
if [ -d "$ROOT/web" ]; then
  say "Flutter Web output web/"
  cp -a "$ROOT/web/." "$STAGE/web/"
fi

# ---------- 5. metadata ----------
say "writing META.txt"
{
  echo "== SekaiNook full snapshot =="
  echo "time     : $TS"
  echo "host     : $(hostname)"
  echo "kernel   : $(uname -r)"
  echo "os       : $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"
  echo "node     : $(node -v 2>/dev/null || echo '-')"
  echo ""
  echo "== database row counts =="
  sqlite3 "$STAGE/data/sekainook.db" "
    SELECT 'family_ledger  '||COUNT(*) FROM family_ledger UNION ALL
    SELECT 'weekly_plans   '||COUNT(*) FROM weekly_plans  UNION ALL
    SELECT 'notifications  '||COUNT(*) FROM notifications UNION ALL
    SELECT 'settings       '||COUNT(*) FROM settings      UNION ALL
    SELECT 'changelog      '||COUNT(*) FROM changelog
  " 2>/dev/null || echo "(failed to read row counts)"
  echo ""
  echo "== image file count =="
  find "$STAGE/data/r2" -type f 2>/dev/null | wc -l
  echo ""
  echo "== code version =="
  git --git-dir="$BARE" log -1 --format='%H %ci %s' 2>/dev/null || echo "(unreadable)"
  echo ""
  echo "!! This archive contains .env (ADMIN_PASSWORD) and sudoers.    !!"
  echo "!! Never upload it to any public location.                     !!"
} | tee "$STAGE/META.txt"

# ---------- 6. restore guide ----------
cat > "$STAGE/RESTORE.md" <<'EOM'
# SekaiNook 完整快照 · 恢复指南

假定目标机：Ubuntu 24.04；若公网 IP 变了，还要同步改 App 的 `apiBase`（编译期常量，得重新打包）。

## 1. 装基础组件

```bash
sudo apt update
sudo apt install -y nginx sqlite3 git rsync
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
sudo useradd -m -s /bin/bash sekainook 2>/dev/null || true
```

## 2. 解开快照

```bash
sudo mkdir -p /opt/sekainook
sudo tar -xzf sekainook-full-*.tar.gz -C /opt/sekainook
cd /opt/sekainook && ls -la      # 应看到 data/ etc/ git-hooks/ git-repo/ web/ .env META.txt
```

## 3. 放回系统配置

```bash
sudo cp etc/nginx-sekainook.conf /etc/nginx/sites-available/sekainook
sudo ln -sf /etc/nginx/sites-available/sekainook /etc/nginx/sites-enabled/sekainook
sudo cp etc/sekainook.service    /etc/systemd/system/
sudo cp etc/sudoers-sekainook    /etc/sudoers.d/sekainook
sudo chmod 440 /etc/sudoers.d/sekainook
sudo cp etc/cron-sekainook-backup /etc/cron.d/sekainook-backup
sudo cp etc/.htpasswd* /etc/nginx/ 2>/dev/null || true
# 只在目标机确实有 nginx.conf 定制时才覆盖它，否则保持发行版默认更安全
sudo nginx -t && sudo systemctl reload nginx
```

## 4. 恢复裸仓库与部署钩子

```bash
sudo mv git-repo/sekainook.git /opt/sekainook.git
sudo cp git-hooks/post-receive /opt/sekainook.git/hooks/
sudo chmod +x /opt/sekainook.git/hooks/post-receive
sudo chown -R ubuntu:ubuntu /opt/sekainook.git      # 改成目标机的登录用户
```

## 5. 装依赖并起服务

```bash
cd /opt/sekainook/server && npm i
cd /opt/sekainook
sudo chown -R sekainook:sekainook data
sudo systemctl daemon-reload
sudo systemctl enable --now sekainook
journalctl -u sekainook -n 30 --no-pager
```

## 6. 验证

```bash
sqlite3 data/sekainook.db "SELECT COUNT(*) FROM family_ledger;"   # 与 META.txt 对比
curl -s http://127.0.0.1:8788/api/ledger/summary
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1/       # 期望 401（Basic Auth）或 200
```

前端在 `web/`，nginx 的 `root` 指向它。
EOM

# ---------- 7. pack ----------
say "packing -> $OUT/$NAME"
tar -C "$STAGE" -czf "$OUT/$NAME" .
( cd "$OUT" && sha256sum "$NAME" > "$NAME.sha256" )

say "done"
ls -lh "$OUT/$NAME" "$OUT/$NAME.sha256"
echo
echo "Next, on your PC:"
echo "  scp <user>@<IP>:$OUT/$NAME* <local dir>/"
echo
echo "This archive holds .env and sudoers -> local only, never a cloud drive."
