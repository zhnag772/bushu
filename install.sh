#!/usr/bin/env bash
set -euo pipefail
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
LANG=en_US.UTF-8

######## 参数 ########
MAIL_USER="lambert"
PASS="mdyS2FZrNixr"
DOMAINS=("$@")
[[ ${#DOMAINS[@]} -eq 0 ]] && { echo "用法: $0 <域名1> [域名2] ..." >&2; exit 1; }

######## 防火墙 ########
for p in 25 143 465 587 993; do ufw allow "$p" &>/dev/null || true; done

######## 装 Docker ########
if ! command -v docker &>/dev/null; then
  apt-get update -qq
  apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

######## 路径 ########
DATA_DIR="${PWD}/docker-data/dms/mail-data"
STATE_DIR="${PWD}/docker-data/dms/mail-state"
CONFIG_DIR="${PWD}/docker-data/dms/config"
mkdir -p "$DATA_DIR" "$STATE_DIR" "$CONFIG_DIR"

######## 绝对清零 ########
echo "========== 绝对清零（容器+卷+状态） =========="
docker compose -f mailserver/compose.yaml down --volumes --remove-orphans &>/dev/null || true
docker rm -f mailserver &>/dev/null || true
rm -rf "${DATA_DIR:?}"/* "${STATE_DIR:?}"/*
# config 留空，让下面一次性容器写

######## 用一次性容器写账号（直接写卷，而非宿主 config） ########
echo "========== 一次性容器写账号 =========="
for DOM in "${DOMAINS[@]}"; do
  EMAIL="${MAIL_USER}@${DOM}"
  docker run --rm \
    -v "${DATA_DIR}:/var/mail" \
    -v "${STATE_DIR}:/var/mail-state" \
    -e ENABLE_CLAMAV=0 \
    -e ENABLE_FAIL2BAN=0 \
    mailserver/docker-mailserver:15.1.0 \
    setup email add "${EMAIL}" "${PASS}"

  docker run --rm \
    -v "${STATE_DIR}:/var/mail-state" \
    -e ENABLE_CLAMAV=0 \
    -e ENABLE_FAIL2BAN=0 \
    mailserver/docker-mailserver:15.1.0 \
    setup alias add "@${DOM}" "${EMAIL}"
done

######## 改 hostname 并启动 ########
MAIN_FQDN="mail.${DOMAINS[0]}"
cd mailserver
sed -i "s/hostname: .*/hostname: ${MAIN_FQDN}/" compose.yaml
echo "========== 启动正式容器 =========="
docker compose up -d

######## 等待账号生效 ########
for i in {1..60}; do
  if docker exec mailserver doveadm user "${MAIL_USER}@${DOMAINS[0]}" &>/dev/null; then
    echo "========== Dovecot 已识别账号，服务就绪！ =========="
    break
  fi
  sleep 1
done

######## 汇总 ########
cat <<EOF
======================================================
✅ 多域名邮件服务器已启动（无加密，端口全开）
------------------------------------------------------
主容器域名 : ${MAIN_FQDN}
邮箱用户名 : ${MAIL_USER}
统一密码   : ${PASS}
------------------------------------------------------
支持域名:
$(printf '  • %s\n' "${DOMAINS[@]}")
------------------------------------------------------
账户与别名:
$(for d in "${DOMAINS[@]}"; do printf '  %s@%s (catch-all: @%s)\n' "$MAIL_USER" "$d" "$d"; done)
------------------------------------------------------
IMAP : 143 / 993
SMTP : 25 / 465 / 587
======================================================
EOF
