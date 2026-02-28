#!/bin/bash
LANG=en_US.UTF-8

# =========================
# 默认配置
# =========================
MAIL_USER="lambert"
PASS="mdyS2FZrNixr"

# =========================
# 接收多个域名参数，并清理空格
# =========================
DOMAINS_RAW=("$@")
DOMAINS=()

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
# 放行端口（写死 8080）
# =========================
echo -e "放行端口: 25, 143, 465, 587, 993, 8080"
for port in 25 143 465 587 993 8080; do
    ufw allow "$port" >/dev/null 2>&1 || true
done

# =========================
# 准备目录
# =========================
mkdir -p ./mailserver

# =========================
# 下载配置文件
# =========================
echo -e "下载 compose.yaml..."
curl -fsSL https://raw.githubusercontent.com/zhnag772/bushu/refs/heads/main/mailserver/compose.yaml \
    -o ./mailserver/compose.yaml

# =========================
# 安装 Docker
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

# =========================
# 启动 mailserver
# =========================
cd mailserver || { echo "错误: 未找到 mailserver 目录"; exit 1; }

echo -e "启动 mailserver 容器..."
docker compose up -d
sleep 10

# =========================
# 创建邮箱和别名
# =========================
echo -e "\n创建邮箱账户和 catch-all 别名:"
for DOMAIN in "${DOMAINS[@]}"; do
    EMAIL="${MAIL_USER}@${DOMAIN}"
    echo -e "  ➕ 创建邮箱: ${EMAIL}"
    docker exec -i mailserver setup email add "${EMAIL}" "${PASS}" 2>/dev/null || true

    echo -e "  🎯 创建 catch-all: @${DOMAIN} -> ${EMAIL}"
    docker exec -i mailserver setup alias add "@${DOMAIN}" "${EMAIL}" 2>/dev/null || true
done

cd ..

# =========================
# 部署 mail-monitor 服务
# =========================
echo -e "\n部署 mail-monitor 服务..."

# 获取当前目录
CURRENT_DIR=$(pwd)
MONITOR_BIN="${CURRENT_DIR}/monitor"

# 下载 monitor 二进制文件
echo -e "  ⬇️  下载 monitor 二进制文件..."
curl -fsSL https://raw.githubusercontent.com/zhnag772/bushu/refs/heads/main/monitor \
    -o "${MONITOR_BIN}" || {
    echo -e "  ❌ 下载失败，请检查网络或手动放置 monitor 文件到 ${CURRENT_DIR}/monitor"
    exit 1
}

# 设置可执行权限
chmod +x "${MONITOR_BIN}"

# 创建 systemd 服务文件
cat > /etc/systemd/system/mail-monitor.service << EOF
[Unit]
Description=Mail Monitor Service
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
WorkingDirectory=${CURRENT_DIR}
ExecStart=${MONITOR_BIN}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 重新加载 systemd 并启动服务
systemctl daemon-reload
systemctl enable mail-monitor.service

# 如果服务在运行，先停止
systemctl stop mail-monitor.service 2>/dev/null || true

# 启动服务
systemctl start mail-monitor.service
sleep 2

# 检查状态
if systemctl is-active --quiet mail-monitor.service; then
    echo -e "  ✅ mail-monitor 服务已启动"
else
    echo -e "  ❌ mail-monitor 服务启动失败，请检查日志: journalctl -u mail-monitor -f"
fi

# =========================
# 输出汇总信息
# =========================
IP=$(curl -s ifconfig.me 2>/dev/null || echo "你的IP")

cat <<EOF

======================================================
✅ 邮件服务器已启动（多域名 + Monitor 监控）
------------------------------------------------------
邮箱用户名 : ${MAIL_USER}
统一密码   : ${PASS}
------------------------------------------------------
支持域名列表:
$(printf '  • %s\n' "${DOMAINS[@]}")
------------------------------------------------------
账户与别名:
$(for d in "${DOMAINS[@]}"; do printf '  %s@%s (catch-all: @%s)\n' "$MAIL_USER" "$d" "$d"; done)
------------------------------------------------------
IMAP 端口 : 143 / 993
SMTP 端口 : 25 / 465 / 587
API 端口  : 8080
------------------------------------------------------
Monitor API:
  查询邮件: POST http://${IP}:8080/query
  清空数据: POST http://${IP}:8080/clear
------------------------------------------------------
常用命令:
  查看邮件日志: docker logs -f mailserver
  查看API日志 : journalctl -u mail-monitor -f
  重启Monitor: systemctl restart mail-monitor
  停止Monitor: systemctl stop mail-monitor
======================================================

EOF
