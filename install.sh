#!/usr/bin/env bash
#--------------------------------------------------
# Docker-MailServer 一键部署脚本（Ubuntu 22.04）—— ROOT 专用版
#--------------------------------------------------
set -euo pipefail

############################ 用户唯一需要改的地方 ############################
MANUAL_FQDN=""        # 手动填 mail.example.com；留空自动探测
DOMAIN=""             # 留空自动算
MAIL_USER="lambert"   # 邮箱 @ 前用户名
############################################################################

# 颜色
GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
log(){ echo -e "${GREEN}[$(date +%F\ %T)]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*" >&2; }

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

############################ 3. FQDN / 域名 ############################
if [[ -n "$MANUAL_FQDN" ]]; then
  FQDN="$MANUAL_FQDN"
  DOMAIN="${DOMAIN:-${FQDN#*.}}"
else
  FQDN="$(hostname -f 2>/dev/null || hostname)"
  [[ "$FQDN" =~ \. ]] || FQDN="mail.$FQDN"
  DOMAIN="${FQDN#*.}"
fi
log "使用 FQDN: ${FQDN}"
log "使用域名: ${DOMAIN}"

############################ 4. 拉取模板 ############################
[ -f compose.yaml ] && { warn "compose.yaml 已存在，备份为 compose.yaml.bak"; mv compose.yaml compose.yaml.bak; }
[ -f mailserver.env ] && { warn "mailserver.env 已存在，备份为 mailserver.env.bak"; mv mailserver.env mailserver.env.bak; }

DMS_GITHUB_URL="https://raw.githubusercontent.com/docker-mailserver/docker-mailserver/master"
log "拉取 compose.yaml 与 mailserver.env"
wget -q "${DMS_GITHUB_URL}/compose.yaml"
wget -q "${DMS_GITHUB_URL}/mailserver.env"
sed -i "s/hostname: .*/hostname: ${FQDN}/" compose.yaml

############################ 5. 启动容器 ############################
log "启动 mailserver 容器"
docker compose up -d
until docker exec mailserver ss -ln | grep -q :25; do sleep 2; done

############################ 6. 账号 & catch-all ############################
PASS=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
log "创建邮箱账号: ${MAIL_USER}@${DOMAIN}  密码: ${PASS}"
docker exec -it mailserver setup email add "${MAIL_USER}@${DOMAIN}" "${PASS}"
log "创建 catch-all 别名: @${DOMAIN} -> ${MAIL_USER}@${DOMAIN}"
docker exec -it mailserver setup alias add "@${DOMAIN}" "${MAIL_USER}@${DOMAIN}"

############################ 7. 安装 gost ############################
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
FQDN :  ${FQDN}
域名 :  ${DOMAIN}
邮箱 :  ${MAIL_USER}@${DOMAIN}
密码 :  ${PASS}
------------------------------------------------------
IMAP 端口: 143 / 993
SMTP 端口: 25 / 465 / 587
catch-all: @${DOMAIN} -> ${MAIL_USER}@${DOMAIN}
======================================================
EOF