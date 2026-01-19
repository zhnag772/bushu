#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
LANG=en_US.UTF-8

# =========================
# 默认配置
# =========================
MAIL_USER="lambert"
PASS="mdyS2FZrNixr"  # 所有账户使用相同密码

# =========================
# 接收多个域名参数
# =========================
DOMAINS=("$@")
if [[ ${#DOMAINS[@]} -eq 0 ]]; then
    echo -e "请指定至少一个域名: $0 <域名1> [域名2] [域名3] ..." >&2
    exit 1
fi

echo -e "使用域名: ${DOMAINS[*]}"

# =========================
# 放行邮件端口
# =========================
echo -e "放行邮件端口: 25, 143, 465, 587, 993"
for port in 25 143 465 587 993; do
    ufw allow "$port" >/dev/null 2>&1 || true
done

# =========================
# 安装 Docker（如未安装）
# =========================
if ! command -v docker &>/dev/null; then
    echo -e "安装 Docker..."
    apt-get update -qq
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# =========================
# 设置主域名（用于容器 hostname）
# 使用第一个域名为 FQDN
# =========================
MANUAL_FQDN="mail.${DOMAINS[0]}"
echo -e "容器主机名: ${MANUAL_FQDN}"

# =========================
# 提前把账号写进 config 目录，避免 120 s 超时
# =========================
CONFIG_DIR="${PWD}/docker-data/dms/config"
mkdir -p "${CONFIG_DIR}"

echo -e "\n预创建邮箱账户和 catch-all 别名:"
for DOMAIN in "${DOMAINS[@]}"; do
    EMAIL="${MAIL_USER}@${DOMAIN}"
    # 写账号（postfixaccounts 格式：user@domain|{SHA512}密码）
    docker run --rm \
        -v "${CONFIG_DIR}:/tmp/docker-mailserver" \
        -v "${PWD}/docker-data/dms/mail-data:/var/mail" \
        mailserver/docker-mailserver:15.1.0 \
        setup email add "${EMAIL}" "${PASS}"

    # 写 catch-all 别名（alias 格式：@domain user@domain）
    docker run --rm \
        -v "${CONFIG_DIR}:/tmp/docker-mailserver" \
        mailserver/docker-mailserver:15.1.0 \
        setup alias add "@${DOMAIN}" "${EMAIL}"
done

# =========================
# 启动 mailserver
# =========================
cd mailserver || { echo "错误: 未找到 mailserver 目录"; exit 1; }

# 修改 compose.yaml 中的 hostname
sed -i "s/hostname: .*/hostname: ${MANUAL_FQDN}/" compose.yaml

echo -e "启动 mailserver 容器..."
docker compose up -d

cd ..

# =========================
# 输出汇总信息
# =========================
cat <<EOF
======================================================
✅ 邮件服务器已启动（多域名支持）
------------------------------------------------------
主容器域名 : ${MANUAL_FQDN}
邮箱用户名 : ${MAIL_USER}
统一密码   : ${PASS}
------------------------------------------------------
支持域名列表:
$(printf '  • %s\n' "${DOMAINS[@]}")
------------------------------------------------------
账户与别名:
$(for d in "${DOMAINS[@]}"; do printf '  %s@%s (catch-all: @%s)\n' "$MAIL_USER" "$d" "$d"; done)
------------------------------------------------------
IMAP 端口: 143 / 993
SMTP 端口: 25 / 465 / 587
------------------------------------------------------
添加新邮箱: docker exec -i mailserver setup email add <邮箱> <密码>
添加别名:   docker exec -i mailserver setup alias add @域名 <目标邮箱>
======================================================
EOF
