#!/bin/sh
# SekaiNook 每日备份（容器化部署版）
#
#   - SQLite 热备：在 backend 容器内做（容器里有 better-sqlite3 驱动），
#     先写成容器内的临时文件，再 docker cp 出来。
#     ⚠️ 不要直接从宿主机 cp 那个 .db 文件：库跑在 WAL 模式，
#     活的 -wal 文件由容器持有，直接拷出来可能是不一致的半截数据。
#   - r2/ 是宿主机 bind mount 上的普通目录 → 直接 tar。
#   - 只保留最近 14 天。
#
# 由 /etc/cron.d/sekainook-backup 每天 03:00 调用。
# 终端输出一律英文：Windows PowerShell 控制台按 GBK 解码远端输出，中文会乱码。

set -e

ROOT=/opt/sekainook
BACKUP_DIR=/opt/sekainook-backups
CONTAINER=sekainook-backend
KEEP_DAYS=14
STAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "${BACKUP_DIR}"

# --- 1. 数据库热备 ----------------------------------------------------
TMPNAME="backup-tmp-${STAMP}.sqlite3"

docker exec "${CONTAINER}" node -e '
const D = require("/app/server/node_modules/better-sqlite3");
const src = new D("/app/data/sekainook.db", { readonly: true });
src.backup(process.argv[1]).then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
' "/app/data/${TMPNAME}"

docker cp "${CONTAINER}:/app/data/${TMPNAME}" "${BACKUP_DIR}/db-${STAMP}.sqlite3"
docker exec "${CONTAINER}" rm -f "/app/data/${TMPNAME}"

# --- 2. 图片（文件系统模拟的 R2） --------------------------------------
if [ -d "${ROOT}/data/r2" ]; then
  tar -czf "${BACKUP_DIR}/r2-${STAMP}.tar.gz" -C "${ROOT}/data" r2
fi

# --- 3. 清理过期备份 --------------------------------------------------
find "${BACKUP_DIR}" -name '*.sqlite3' -mtime +${KEEP_DAYS} -delete 2>/dev/null || true
find "${BACKUP_DIR}" -name '*.tar.gz' -mtime +${KEEP_DAYS} -delete 2>/dev/null || true

echo "[backup] $(date '+%F %T') done -> ${BACKUP_DIR}"
