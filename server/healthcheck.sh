#!/usr/bin/env bash
# 服务器体检 —— 只读，不安装、不改配置、不写业务数据。
#
# 用途：在这台 2C4G 上「再装点别的服务」之前，先看清还剩多少内存/磁盘/端口/流量。
# 用法：
#   sudo bash /opt/sekainook/server/healthcheck.sh                # 直接看
#   sudo bash /opt/sekainook/server/healthcheck.sh > /tmp/r.txt   # 存文件再 cat 出来
#
# 输出分 12 段，方便只贴需要的部分。

set -u
LC_ALL=C
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

line() { printf '\n===== %s =====\n' "$1"; }

line "0. 身份"
# shellcheck disable=SC1091
. /etc/os-release 2>/dev/null || true
echo "系统     : ${PRETTY_NAME:-unknown}"
echo "内核     : $(uname -r)"
echo "主机名   : $(hostname)"
echo "运行时长 : $(uptime -p 2>/dev/null || uptime)"
echo "当前时间 : $(date '+%F %T %Z')"

line "1. CPU / 负载"
echo "核数: $(nproc)"
uptime
echo "--- 按 CPU 排序 top5 ---"
ps -eo pcpu,pmem,rss,comm --sort=-pcpu 2>/dev/null | head -6

line "2. 内存 / swap"
free -h
echo "--- 按内存排序 top5 (rss 单位 KB) ---"
ps -eo pmem,rss,comm --sort=-pmem 2>/dev/null | head -6

line "3. 磁盘"
df -h / 2>/dev/null
echo "--- inode ---"
df -i / 2>/dev/null | tail -1
echo "--- 各目录占用（升序，看大头在最后）---"
du -sh /opt/* /var/log /var/lib/docker /opt/sekainook-backups 2>/dev/null | sort -h
echo "--- / 一级目录 ---"
du -sh --exclude=/proc --exclude=/sys /* 2>/dev/null | sort -h | tail -8

line "4. 监听端口"
ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null
echo "--- UDP ---"
ss -ulnp 2>/dev/null | head -10

line "5. 运行中的服务"
systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null | awk '{print $1}'
echo "--- 失败的单元 ---"
systemctl --failed --no-pager --no-legend 2>/dev/null || echo "(读不到)"

line "6. nginx 现状"
nginx -v 2>&1
echo "--- 站点配置要点 ---"
nginx -T 2>/dev/null | grep -E '^[[:space:]]*(server_name|listen|location|auth_basic|proxy_pass|root)' | head -40 \
  || echo "(nginx -T 需 root)"

line "7. 定时任务"
systemctl list-timers --all --no-pager 2>/dev/null | head -12
echo "--- /etc/cron.d ---"
ls -1 /etc/cron.d/ 2>/dev/null
echo "--- root crontab ---"
crontab -l 2>/dev/null | grep -v '^#' | head -10

line "8. 已装工具"
for c in docker docker-compose node npm nginx sqlite3 git wget curl unzip jq python3 pip3 ufw fail2ban-client certbot; do
  printf '%-16s %s\n' "$c" "$(command -v "$c" 2>/dev/null || echo '-')"
done
echo "--- 版本 ---"
docker --version 2>/dev/null
node -v 2>/dev/null
nginx -v 2>&1 | head -1
sqlite3 --version 2>/dev/null | head -1

line "9. SekaiNook 现状"
echo "服务状态 : $(systemctl is-active sekainook 2>/dev/null)"
systemctl show sekainook -p MemoryCurrent -p MainPID 2>/dev/null
echo "--- data 目录 ---"
ls -lah /opt/sekainook/data/ 2>/dev/null
du -sh /opt/sekainook/data/r2 /opt/sekainook/web /opt/flutter-sdk 2>/dev/null
echo "--- 数据库 ---"
[ -f /opt/sekainook/data/sekainook.db ] && ls -lh /opt/sekainook/data/sekainook.db
[ -f /opt/sekainook/data/sekainook.db ] && sqlite3 /opt/sekainook/data/sekainook.db '.tables' 2>/dev/null
echo "--- 备份 ---"
ls -lt /opt/sekainook-backups 2>/dev/null | head -6
du -sh /opt/sekainook-backups 2>/dev/null

line "10. 日志占用"
journalctl --disk-usage 2>/dev/null
du -sh /var/log/* 2>/dev/null | sort -h | tail -5

line "11. 防火墙"
ufw status 2>/dev/null | head -6 || echo "(未装 ufw)"
echo "--- nft/iptables 摘要 ---"
nft list ruleset 2>/dev/null | head -5 || iptables -S 2>/dev/null | head -8 || true

line "12. 流量（开机以来累计，不等于本月用量）"
cat /proc/net/dev 2>/dev/null | grep -vE '^\s*(Inter|face)' | awk '{printf "%-10s RX %.1f GB  TX %.1f GB\n", $1, $2/1073741824, $10/1073741824}'
echo "提示：本月流量包用量在腾讯云控制台 → 轻量应用服务器 → 实例概览 看，本脚本读不到。"

line "完"
