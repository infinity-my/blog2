#!/usr/bin/env bash
# 日常更新部署：本机构建前后端 → 上传服务器 → 重启后端服务。
# 首次部署请先看同目录 README.md；本脚本只负责之后的每次更新。
# 用法：bash deploy.sh（在 Windows 上用 Git Bash 运行）
set -euo pipefail

# ===== 按实际情况修改这五行 =====
SERVER="root@your-server-ip"     # SSH 目标
WEB_ROOT="/var/www/blog-qd"      # 前台静态目录，与 Caddyfile/nginx 配置一致
ADMIN_WEB_ROOT="/var/www/blog-ht" # 管理后台静态目录（域名 /admin/ 路径）
BACKEND_DIR="/opt/blog-hd"       # 后端部署目录，与 systemd 单元一致
SERVICE_NAME="blog-hd"           # systemd 服务名
# ===============================

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> [1/5] 构建前台（blog-qd）"
(cd "$ROOT/blog-qd" && npm run build)

echo "==> [2/5] 构建管理后台（blog-ht）"
(cd "$ROOT/blog-ht" && npm run build)

echo "==> [3/5] 构建后端（blog-hd）"
(cd "$ROOT/blog-hd" && ./gradlew bootJar --console=plain -q)
JAR="$(ls -t "$ROOT/blog-hd/build/libs/"*.jar | head -n 1)"
echo "    产物：$(basename "$JAR")"

echo "==> [4/5] 上传到 $SERVER"
ssh "$SERVER" "mkdir -p '$WEB_ROOT' '$ADMIN_WEB_ROOT' '$BACKEND_DIR'"
# 只清前端入口与带哈希的资源目录，避免旧产物越积越多
ssh "$SERVER" "rm -rf '$WEB_ROOT/assets' '$WEB_ROOT/index.html' '$ADMIN_WEB_ROOT/assets' '$ADMIN_WEB_ROOT/index.html'"
scp -r "$ROOT/blog-qd/dist/." "$SERVER:$WEB_ROOT/"
scp -r "$ROOT/blog-ht/dist/." "$SERVER:$ADMIN_WEB_ROOT/"
# 固定名 blog-hd.jar，systemd 的 ExecStart 不用跟着版本号变
scp "$JAR" "$SERVER:$BACKEND_DIR/blog-hd.jar"

echo "==> [5/5] 重启后端服务 $SERVICE_NAME"
ssh "$SERVER" "systemctl restart '$SERVICE_NAME' && sleep 2 && systemctl --no-pager -l status '$SERVICE_NAME' | head -n 6"

echo "==> 完成。打开 https://你的域名 验证：登录、留言板、退出全链路。"
