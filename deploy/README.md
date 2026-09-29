# 部署手册（HTTPS 上线）

架构：TLS 卸载在反向代理上，后端保持 HTTP 只听本机，全站同一域名同源。

```
浏览器 ──HTTPS 443──> Caddy/Nginx ──┬──> 前台静态文件 /var/www/blog-qd（blog-qd/dist）
                                    ├──> /admin 后台静态 /var/www/blog-ht（blog-ht/dist）
                                    └──> /api 反代 ──> Spring Boot 127.0.0.1:8080
```

这套结构与开发时的 vite 代理同构（`/api` 同源转发），前端代码零改动。
本目录文件与服务器路径的对应关系：

| 本目录文件        | 服务器位置                        | 作用                     |
| ----------------- | --------------------------------- | ------------------------ |
| `Caddyfile`       | `/etc/caddy/Caddyfile`            | 反代 + 自动证书（推荐）  |
| `nginx-blog.conf` | `/etc/nginx/sites-available/blog` | 反代 + certbot 证书（备选） |
| `systemd/blog-hd.service` | `/etc/systemd/system/blog-hd.service` | 后端服务 + 生产环境变量 |
| `server-init.sh` | 全新服务器一次性初始化（在服务器上以 root 运行） | 装 JDK/MySQL/Caddy、建库、写单元 |
| `deploy.sh`       | 留在本机，日常更新用              | 构建 → 上传 → 重启       |

> 注意：`deploy/` 在 gr-blog 顶层，不属于 blog-hd / blog-qd 任何一个子仓库，不会被 git 跟踪。
> 若想版本化，可自行拷贝进其中一个仓库；**真实口令永远只写在服务器上的 systemd 单元里**。

## 首次部署（一次性）

> 快捷路径：Ubuntu/Debian 全新服务器可用 `server-init.sh` 自动完成第 2-5 步
> （用法见脚本头部注释；口令在服务器上交互输入/随机生成，不落仓库）。

1. **域名**：解析到服务器；国内服务器需 ICP 备案，否则 80/443 开不了。
2. **服务器基础**：装 JDK 21、MySQL；建系统用户和目录：
   ```bash
   useradd -r -s /usr/sbin/nologin blog
   mkdir -p /opt/blog-hd /var/www/blog-qd /var/www/blog-ht
   ```
3. **数据库**：建库、建专用账号并授权（口令须与 systemd 单元里的 `DB_PASSWORD` 一致；
   schema 在后端仓库 `blog-hd/src/main/resources/sql/`）：
   ```bash
   mysql -u root -p -e "CREATE DATABASE blog_hd CHARACTER SET utf8mb4; \
     CREATE USER 'blog'@'localhost' IDENTIFIED BY '改成真实密码'; \
     GRANT ALL PRIVILEGES ON blog_hd.* TO 'blog'@'localhost';"
   mysql -u root -p blog_hd < blog-hd/src/main/resources/sql/schema.sql
   # 需要种子数据时再导 data.sql
   ```
4. **后端服务**：按 `systemd/blog-hd.service` 注释填写真实口令（COOKIE_SECURE=true、
   RESUME_PASSWORD、ADMIN_USERNAME、ADMIN_PASSWORD、DB_PASSWORD），
   装载并启动。后端不内置任何默认口令：RESUME_PASSWORD 不填则简历解锁口令一直 503；
   ADMIN_USERNAME / ADMIN_PASSWORD 不填则拒绝启动。
   首次启动会按 `ADMIN_USERNAME` / `ADMIN_PASSWORD` 自动种入后台管理员（`admin_account` 表，
   表里已有同名账号则跳过）；后台「账号管理」里改的口令以表里为准，重启不会被配置盖回。
   忘了后台口令时，删掉表里对应行再重启即可按配置重新种入。
   **升级已有部署**：旧版本内置的默认管理员口令已移除。若线上当初用的就是默认口令，
   登录后台「账号管理」改密即可；想让环境变量生效则必须删掉 `admin_account` 旧行再重启
   （skip-if-exists 不会拿环境变量覆盖已有账号）。
5. **HTTPS 反代**：Caddy（推荐，改域名后放进 /etc/caddy/）或 nginx + certbot，二选一；
   防火墙放行 80/443，后端 8080 不对公网开放。
6. **首次上线产物**：在项目根目录跑 `bash deploy/deploy.sh`（先改脚本顶部的 SSH 目标等四行）。

## 日常更新

```bash
bash deploy/deploy.sh
```

## 上线验证清单

- [ ] `http://域名` 自动跳转 `https://`
- [ ] 开发者工具 → Application → Cookies：`SESSION` 带 `HttpOnly`、`Secure` 标志
- [ ] 注册 → 登录 → 留言（身份带昵称）→ 退出 → 再登录，全链路正常
- [ ] `https://域名/admin/` 打开管理后台，用 systemd 单元里的 ADMIN_USERNAME 登录成功
- [ ] 密码连错 5 次出现「尝试太频繁」限流提示
- [ ] 直接访问 `http://服务器IP:8080` 应不通（后端未暴露公网）

## 常见问题

- **证书没签下来**：检查域名解析是否生效、防火墙 80 端口是否放行（ACME 验证用）。
- **限流计数疑似异常/所有访客共享计数**：后端默认已按 NATIVE 从 X-Forwarded-For 取真实客户端 IP；
  若有人把 `FORWARD_HEADERS_STRATEGY` 显式设成了 `none`，所有请求会被当成同一个 IP（127.0.0.1），
  全站共享限流桶。仅本地裸跑（无代理直连）才需要 `none`。
- **刷新页面 404**：反代的 SPA 回落（try_files → index.html）没配好。
- **登录后一刷新就掉**：多半是 `COOKIE_SECURE=true` 但站点还在用 HTTP 访问；
  先确保 HTTPS 通了再开这个开关。
