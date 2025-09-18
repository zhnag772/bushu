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

############################ 1. 放行端口 ############################
log "放行邮件端口"
for port in 25 143 465 587 993 1280; do ufw allow "$port" >/dev/null 2>&1 || true; done

############################ 2. 安装 Docker ############################
if ! command -v docker &>/dev/null; then
  log "安装 Docker"
  apt-get update -qq
  apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

############################ 4. 拉取模板 ############################
mkdir -p mailserver
cd mailserver
DMS_GITHUB_URL="https://raw.githubusercontent.com/docker-mailserver/docker-mailserver/master"
log "拉取 compose.yaml 与 mailserver.env"
wget -q "${DMS_GITHUB_URL}/compose.yaml"
wget -q "${DMS_GITHUB_URL}/mailserver.env"
sed -i "s/hostname: .*/hostname: ${MANUAL_FQDN}/" compose.yaml
############################ 5. 启动容器 ############################
log "启动 mailserver 容器"
docker compose up -d
