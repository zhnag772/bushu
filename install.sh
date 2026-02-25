#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:～/bin
export PATH
LANG=en_US.UTF-8

# =========================
# 默认配置
# =========================
MAIL_USER="lambert"
PASS="mdyS2FZrNixr"  # 所有账户使用相同密码

# =========================
# 接收多个域名参数，并清理空格
# =========================
DOMAINS_RAW=("$@")
DOMAINS=()

# 清理每个参数：去前后空格，跳过空值
for raw in "${DOMAINS_RAW[@]}"; do
    trimmed=$(echo "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ -n "$trimmed" ]]; then
        DOMAINS+=("$trimmed")
    fi
done

if [[ ${#DOMAINS[@]} -eq 0 ]]; then
    echo -e "请指定至少一个非空域名: $0 <域名1> [域名2] ..." >&2
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

# 检查 ./mailserver 目录是否存在，如果不存在则创建
if [ ! -d "./mailserver" ]; then
  echo "目录 ./mailserver 不存在，正在创建..."
  mkdir -p "./mailserver"
fi
# 下载 compose.yaml 文件到 ./mailserver 目录
curl -fsSL https://raw.githubusercontent.com/zhnag772/bushu/refs/heads/main/mailserver/compose.yaml -o ./mailserver/compose.yaml

# =========================
# 安装 Docker（如未安装）
# =========================
if ! command -v docker &>/dev/null; then
    echo -e "安装 Docker..."
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

cd mailserver || { echo "错误: 未找到 mailserver 目录"; exit 1; }

echo -e "启动 mailserver 容器..."
docker compose up -d
sleep 10

# =========================
# 为每个域名创建邮箱和别名
# =========================
echo -e "\n创建邮箱账户和 catch-all 别名:"
for DOMAIN in "${DOMAINS[@]}"; do
    EMAIL="${MAIL_USER}@${DOMAIN}"
    echo -e "  ➕ 创建邮箱: ${EMAIL}"
    docker exec -i mailserver setup email add "${EMAIL}" "${PASS}"

    echo -e "  🎯 创建 catch-all: @${DOMAIN} -> ${EMAIL}"
    docker exec -i mailserver setup alias add "@${DOMAIN}" "${EMAIL}"
done

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
