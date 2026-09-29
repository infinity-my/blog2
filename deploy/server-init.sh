#!/usr/bin/env bash
# 首次部署：在「全新服务器」上以 root 运行，自动完成 README.md 的 1-5 步。
# 前提：Ubuntu/Debian 系 + 域名已解析到本机（国内服务器需先完成 ICP 备案）。
#
# 用法（从本机发起，在 gr-blog 顶层执行）：
#   scp deploy/server-init.sh root@服务器:/
#   scp blog-hd/src/main/resources/sql/schema.sql root@服务器:/root/
#   ssh root@服务器 'bash /server-init.sh your-domain.com'
#
# 之后回到本机：填好 deploy/deploy.sh 顶部的 SERVER，bash deploy/deploy.sh 上传产物。
# 真实口令只在运行时交互输入 / 生成，不落仓库：DB 口令随机生成只写进服务器文件。
set -euo pipefail

DOMAIN="${1:?用法: server-init.sh <域名>}"
[[ $EUID -eq 0 ]] || { echo "请以 root 运行"; exit 1; }

echo "==> [1/6] 安装基础软件（JDK 21 / MySQL / Caddy）"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y openjdk-21-jre-headless mysql-server curl gnupg
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key \
  | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt \
  > /etc/apt/sources.list.d/caddy-stable.list
apt-get update -y && apt-get install -y caddy
java -version 2>&1 | head -n 1

echo "==> [2/6] 建系统用户与目录"
id blog >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin blog
mkdir -p /opt/blog-hd /var/www/blog-qd /var/www/blog-ht
chown blog:blog /opt/blog-hd

echo "==> [3/6] 建库与专用账号（随机 DB 口令）"
DB_PASSWORD="$(openssl rand -hex 16)"
mysql -e "CREATE DATABASE IF NOT EXISTS blog_hd CHARACTER SET utf8mb4;
  CREATE USER IF NOT EXISTS 'blog'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
  ALTER USER 'blog'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
  GRANT ALL PRIVILEGES ON blog_hd.* TO 'blog'@'localhost'; FLUSH PRIVILEGES;"
if [[ -f /root/schema.sql ]]; then
  mysql blog_hd < /root/schema.sql
  echo "    schema.sql 已导入（种子数据 data.sql 按需再手工导入）"
else
  echo "    警告：未找到 /root/schema.sql，请稍后手动导入表结构"
fi

echo "==> [4/6] 收集口令（只写入服务器上的 systemd 单元，不回传仓库）"
read -rp "管理后台用户名 ADMIN_USERNAME: " ADMIN_USERNAME
[[ -n $ADMIN_USERNAME ]] || { echo "用户名不能为空"; exit 1; }
read -rsp "管理后台口令 ADMIN_PASSWORD（建议字母数字，避免引号）: " ADMIN_PASSWORD; echo
[[ -n $ADMIN_PASSWORD ]] || { echo "口令不能为空"; exit 1; }
read -rsp "简历解锁口令 RESUME_PASSWORD（留空 = 简历闸门一直 503）: " RESUME_PASSWORD; echo

cat > /etc/systemd/system/blog-hd.service <<UNIT
[Unit]
Description=blog-hd Spring Boot backend
After=network.target mysql.service

[Service]
User=blog
WorkingDirectory=/opt/blog-hd
ExecStart=/usr/bin/java -jar /opt/blog-hd/blog-hd.jar
Restart=on-failure
RestartSec=5

Environment=SERVER_PORT=8080
Environment=COOKIE_SECURE=true
Environment=RESUME_PASSWORD="$RESUME_PASSWORD"
Environment=ADMIN_USERNAME="$ADMIN_USERNAME"
Environment=ADMIN_PASSWORD="$ADMIN_PASSWORD"
Environment=DB_HOST=127.0.0.1
Environment=DB_PORT=3306
Environment=DB_NAME=blog_hd
Environment=DB_USER=blog
Environment=DB_PASSWORD="$DB_PASSWORD"
Environment=FORWARD_HEADERS_STRATEGY=NATIVE

[Install]
WantedBy=multi-user.target
UNIT
chmod 600 /etc/systemd/system/blog-hd.service
systemctl daemon-reload
systemctl enable blog-hd   # 产物上传后由 deploy.sh 首次启动

echo "==> [5/6] 写入 Caddyfile（域名：$DOMAIN）"
cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak 2>/dev/null || true
cat > /etc/caddy/Caddyfile <<CADDY
$DOMAIN {
	encode gzip

	header {
		X-Content-Type-Options nosniff
		Referrer-Policy strict-origin-when-cross-origin
		Strict-Transport-Security "max-age=63072000; includeSubDomains"
		Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' https: data:; media-src 'self' https:; connect-src 'self'; font-src 'self' data:; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'"
	}

	handle /api/* {
		reverse_proxy localhost:8080
	}

	handle_path /admin/* {
		root * /var/www/blog-ht
		try_files {path} /index.html
		file_server
	}
	redir /admin /admin/ permanent

	handle {
		root * /var/www/blog-qd
		try_files {path} /index.html
		file_server
	}
}
CADDY
systemctl restart caddy

echo "==> [6/6] 防火墙放行 80/443（80 用于 ACME 签证书；8080 不放行）"
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow 80/tcp
  ufw allow 443/tcp
fi

echo
echo "初始化完成。DB 口令（仅此一次展示，已写入 systemd 单元）：$DB_PASSWORD"
echo "下一步：回到本机填好 deploy/deploy.sh 的 SERVER 后运行 bash deploy/deploy.sh。"
