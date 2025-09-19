#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
LANG=en_US.UTF-8


DOMAIN="${1:-}"
[[ -z "$DOMAIN" ]] && { echo -e "请指定域名: $0 <域名>" >&2; exit 1; }
MANUAL_FQDN="mail.${DOMAIN}"
MAIL_USER="lambert"   
echo -e "使用域名: ${DOMAIN}"

echo -e "放行邮件端口"
for port in 25 143 465 587 993; do ufw allow "$port" >/dev/null 2>&1 || true; done

if ! command -v docker &>/dev/null; then
  echo -e "安装 Docker"
  apt-get update -qq
  apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg  | gpg --dearmor -o /usr/share/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu  $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

cd mailserver
sed -i "s/hostname: .*/hostname: ${MANUAL_FQDN}/" compose.yaml
echo -e "启动 mailserver 容器"
docker compose up -d
sleep 10
PASS="mdyS2FZrNixr"
echo -e "创建邮箱账号: ${MAIL_USER}@${DOMAIN}  密码: ${PASS}"
docker exec -i mailserver setup email add "${MAIL_USER}@${DOMAIN}" "${PASS}"
echo -e "创建 catch-all 别名: @${DOMAIN} -> ${MAIL_USER}@${DOMAIN}"
docker exec -i mailserver setup alias add "@${DOMAIN}" "${MAIL_USER}@${DOMAIN}"
cd ..

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
邮箱添加命令 :  docker exec -i mailserver setup email add 邮箱账号 密码
catch-all添加命令 :  docker exec -i mailserver setup alias add @域名 邮箱账号
======================================================
EOF
