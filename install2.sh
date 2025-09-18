#!/usr/bin/env bash
#--------------------------------------------------
# Docker-MailServer 一键部署脚本（Ubuntu 22.04）—— ROOT 专用版
#--------------------------------------------------
set -euo pipefail
############################################################################

# 颜色
GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'; RED='\033[0;31m'
log(){ echo -e "${GREEN}[$(date +%F\ %T)]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
err() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

DOMAIN="${1:-}"
[[ -z "$DOMAIN" ]] && { echo "请指定域名: $0 <域名>" >&2; exit 1; }
MANUAL_FQDN="mail.${DOMAIN}"
MAIL_USER="lambert"   # 邮箱 @ 前用户名
log "使用域名: ${DOMAIN}"
############################ 6. 账号 & catch-all ############################
PASS=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
log "创建邮箱账号: ${MAIL_USER}@${DOMAIN}  密码: ${PASS}"
docker exec -i mailserver setup email add "${MAIL_USER}@${DOMAIN}" "${PASS}"
log "创建 catch-all 别名: @${DOMAIN} -> ${MAIL_USER}@${DOMAIN}"
docker exec -i mailserver setup alias add "@${DOMAIN}" "${MAIL_USER}@${DOMAIN}"
############################ 7. 安装 gost ############################
cd "$(dirname "$0")" || exit 1
chmod +x gost
chmod +x ser
# 替换当前目录 conf.yaml 中的 user / password
[ -f conf.yaml ] && {
  sed -i "s/^user: .*/user: ${MAIL_USER}@${DOMAIN}/" conf.yaml
  sed -i "s/^password: .*/password: ${PASS}/"           conf.yaml
  log "已更新 conf.yaml 中的 user & password"
}

# 8.5 安装 screen（若缺）并后台运行二进制
if ! command -v screen &>/dev/null; then
  log "安装 screen"
  apt-get install -y screen
fi

log "创建 screen 会话 server 并运行 gost"
screen -dmS server -t server bash -c "ser"

############################ 8. 输出 ############################
cat <<EOF
======================================================
邮件服务器已启动
------------------------------------------------------
域名 :  ${DOMAIN}
邮箱 :  ${MAIL_USER}@${DOMAIN}
密码 :  ${PASS}
------------------------------------------------------
IMAP 端口: 143 / 993
SMTP 端口: 25 / 465 / 587
catch-all: @${DOMAIN} -> ${MAIL_USER}@${DOMAIN}
======================================================
EOF
