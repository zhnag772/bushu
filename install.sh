#!/usr/bin/env bash
set -euo pipefail
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
LANG=en_US.UTF-8

# =========================
# 默认配置
# =========================
MAIL_USER="lambert"
PASS="mdyS2FZrNixr"
DOMAINS=("$@")
[[ ${#DOMAINS[@]} -eq 0 ]] && {
  echo "用法: $0 <域名1> [域名2] ..." >&2
  exit 1
}

echo "========== 域名列表 =========="
printf '  • %s\n' "${DOMAINS[@]}"

# =========================
# 防火墙放行（无加密，全开）
# =========================
for port in 25 143 465 587 993; do
  ufw allow "$port" &>/dev/null || true
done

# =========================
# 装 Docker（若缺）
# =========================
if ! command -v docker &>/dev/null; then
  echo "========== 安装 Docker =========="
  apt-get update -qq
  apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

# =========================
# 目录准备
# =========================
CONFIG_DIR="${PWD}/docker-data/dms/config"
DATA_DIR="${PWD}/docker-data/dms/mail-data"
STATE_DIR="${PWD}/docker-data/dms/mail-state"
mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$STATE_DIR"

# =========================
# 强制清理旧状态，确保“首次启动”
# =========================
echo "========== 清理旧状态 =========="
docker compose -f mailserver/compose.yaml down &>/dev/null || true
rm -rf "${DATA_DIR:?}"/* "${STATE_DIR:?}"/*
# 保留 config 目录，下面重新写账号

# =========================
# 预写账号 + catch-all
# =========================
echo "========== 预写账号 =========="
for DOM in "${DOMAINS[@]}"; do
  EMAIL="${MAIL_USER}@${DOM}"
  # 账号
  docker run --rm \
    -v "${CONFIG_DIR}:/tmp/docker-mailserver" \
    -v "${DATA_DIR}:/var/mail" \
    mailserver/docker-mailserver:15.1.0 \
    setup email add "${EMAIL}" "${PASS}"
  # catch-all
  docker run --rm \
    -v "${CONFIG_DIR}:/tmp/docker-mailserver" \
    mailserver/docker-mailserver:15.1.0 \
    setup alias add "@${DOM}" "${EMAIL}"
done

# =========================
# 设置主域名并启动
# =========================
MAIN_FQDN="mail.${DOMAINS[0]}"
echo "========== 启动容器（FQDN: $MAIN_FQDN） =========="
cd mailserver
sed -i "s/hostname: .*/hostname: ${MAIN_FQDN}/" compose.yaml
docker compose up -d

# 等待 health-check 简易版（10 秒内能连 143 即算成功）
for i in {1..30}; do
  if docker exec mailserver doveadm user "${MAIL_USER}@${DOMAINS[0]}" &>/dev/null; then
    echo "========== 邮件服务器就绪 =========="
    break
  fi
  sleep 1
done

# 最终汇总
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
------------------------------------------------------
加账号: docker exec -i mailserver setup email add <邮箱> <密码>
加别名: docker exec -i mailserver setup alias add @域名 <目标邮箱>
======================================================
EOF
