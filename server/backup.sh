#!/bin/sh
# SekaiNook 测试站每日备份
#   - SQLite 用 .backup（在线热备，不锁库、不影响服务）
#   - 图片目录（r2/ 是文件系统模拟的 R2）打包
#   - 只保留最近 14 天
#
# 由 /etc/cron.d/sekainook-backup 每天 03:00 调用。

set -e

ROOT=/opt/sekainook
BACKUP_DIR=/opt/sekainook-backups
KEEP_DAYS=14
STAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "${BACKUP_DIR}"

# 数据库热备
sqlite3 "${ROOT}/data/sekainook.db" ".backup '${BACKUP_DIR}/db-${STAMP}.sqlite3'"

# 图片（没有目录就跳过）
if [ -d "${ROOT}/data/r2" ]; then
  tar -czf "${BACKUP_DIR}/r2-${STAMP}.tar.gz" -C "${ROOT}/data" r2
fi

# 清理过期备份
find "${BACKUP_DIR}" -name '*.sqlite3' -mtime +${KEEP_DAYS} -delete 2>/dev/null || true
find "${BACKUP_DIR}" -name '*.tar.gz' -mtime +${KEEP_DAYS} -delete 2>/dev/null || true

echo "[backup] $(date '+%F %T') 完成 → ${BACKUP_DIR}"
