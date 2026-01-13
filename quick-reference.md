# LiteLLM + WordPress 集成 - 快速参考指南（已迁移）

本文件内容已整理并迁移到 `doc/00-快速上手.md` 与 `doc/README.md`。

建议从根目录 `README.md` 开始。

## 📌 快速开始（5分钟）

### 最快部署方案（使用本仓库模板）

> 适用你当前约束：WordPress 原生跑在 Ubuntu；LiteLLM 用 Docker；同机部署；生产默认不暴露 `:24157` 到公网（仅绑定 127.0.0.1）。

```bash
# 1) 准备目录
sudo mkdir -p /opt/litellm-server/{config,logs,data,observability}
cd /opt/litellm-server

# 2) 拷贝模板文件（把本仓库文件复制到 /opt/litellm-server）
# - docker-compose.core.yml（复制为 docker-compose.yml）
# - docker-compose.observability.yml（可选，复制为 docker-compose.observability.yml）
# - env.example（复制为 .env）
# - config/litellm-config.yaml（按需创建/调整）

# 3) 配置环境变量
cp env.example .env
chmod 600 .env

# 4) 启动核心服务
docker compose up -d

# 5)（可选）启动观测栈：Prometheus/Grafana/Alertmanager/node-exporter/cAdvisor/blackbox
docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d
```

### 手动部署流程

```bash
# 1. 创建项目目录
mkdir -p /opt/litellm-server
cd /opt/litellm-server

# 2. 创建必要文件（见完整方案文档）
# - docker-compose.yml
# - docker-compose.observability.yml（可选）
# - config/litellm-config.yaml
# - .env
# - observability/prometheus/prometheus.yml（可选）

# 3. 启动服务
docker compose up -d

# 4. 验证部署
curl http://localhost:24157/health

# 5. 访问 Web UI
# 生产建议通过反向代理域名访问（不要直连 :24157）
```

---

## 🔑 API Key 管理工作流

### 使用 WordPress 创建 API Key

**流程图:**
```
WordPress 后台
    ↓
LiteLLM → API Key 管理
    ↓
点击"创建新 API Key"
    ↓
填写表单 (名称、模型、预算、RPM)
    ↓
提交
    ↓
LiteLLM 生成密钥
    ↓
WordPress 显示密钥
    ↓
保存密钥用于应用
```

### 使用 cURL 创建 API Key（高级）

```bash
# 命令
curl -X POST http://localhost:24157/key/generate \
  -H "Authorization: Bearer sk-your-master-key" \
  -H "Content-Type: application/json" \
  -d '{
    "key_name": "my-app-key",
    "models": ["gpt-3.5-turbo", "gpt-4"],
    "max_budget": 100,
    "rpm_limit": 100,
    "duration": "30d"
  }'

# 响应示例
{
  "key": "sk-app-xxxxx",
  "key_name": "my-app-key",
  "created": "2026-01-13",
  "status": "active"
}
```

### 列出所有密钥

```bash
curl -H "Authorization: Bearer sk-your-master-key" \
  http://localhost:24157/key/list | jq .
```

### 禁用/删除密钥

```bash
# 禁用密钥
curl -X POST http://localhost:24157/key/block \
  -H "Authorization: Bearer sk-your-master-key" \
  -H "Content-Type: application/json" \
  -d '{"key": "sk-app-xxxxx"}'

# 删除密钥
curl -X POST http://localhost:24157/key/delete \
  -H "Authorization: Bearer sk-your-master-key" \
  -H "Content-Type: application/json" \
  -d '{"key": "sk-app-xxxxx"}'
```

---

## 📊 实时监控指南

### WordPress 仪表板监控

**查看统计数据:**
1. 登录 WordPress 后台
2. 点击 **LiteLLM** 菜单
3. 查看卡片显示:
   - API 请求数
   - 总 Tokens 消耗
   - 总成本
   - 错误率

**查看图表:**
- 请求趋势图（过去7天）
- 成本分布图（按模型）
- 实时 API 调用日志

### LiteLLM Web UI 监控

**访问:** `http://your-server:24157/ui`

**功能:**
- 用户和团队管理
- API 使用分析
- 成本追踪
- 模型性能指标
- 速率限制设置

### Prometheus 监控

**访问（本机回环）:** `http://127.0.0.1:9090`

### Grafana 监控（推荐）

**访问（本机回环）:** `http://127.0.0.1:3000`（默认账号密码见 `docker-compose.observability.yml`，生产务必改掉并接 SSO/LDAP）

### 告警（Alertmanager）

**访问（本机回环）:** `http://127.0.0.1:9093`（生产需配置企业告警渠道）

**常用查询:**
```promql
# API 请求速率
rate(litellm_requests_total[5m])

# 平均响应时间
histogram_quantile(0.95, litellm_request_duration_seconds)

# 错误率
rate(litellm_errors_total[5m])
```

---

## 🔒 安全最佳实践

### 1. Master Key 管理

```bash
# ❌ 不要这样做
export LITELLM_MASTER_KEY="sk-1234"  # 不要在命令行设置

# ✅ 这样做
# 将其放在 .env 文件中
cat > /opt/litellm-server/.env << EOF
LITELLM_MASTER_KEY=sk-your-secure-key
EOF

# 限制文件权限
chmod 600 /opt/litellm-server/.env
```

### 2. API Key 轮换策略

```bash
# 每30天轮换一次密钥
# 创建新密钥
NEW_KEY=$(curl -X POST http://localhost:24157/key/generate ... | jq .key)

# 禁用旧密钥
curl -X POST http://localhost:24157/key/block \
  -d "{\"key\": \"$OLD_KEY\"}"

# 等待应用切换到新密钥
sleep 300

# 删除旧密钥
curl -X POST http://localhost:24157/key/delete \
  -d "{\"key\": \"$OLD_KEY\"}"
```

### 3. 网络安全

```bash
# 配置防火墙（仅允许必要的端口）
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw deny 24157/tcp   # LiteLLM 内部访问
ufw enable

# 或使用 iptables
iptables -A INPUT -p tcp --dport 24157 -s 127.0.0.1 -j ACCEPT
iptables -A INPUT -p tcp --dport 24157 -j DROP
```

### 4. SSL/TLS 配置

```nginx
# 在 nginx.conf 中
server {
    listen 443 ssl http2;
    server_name litellm.yourcompany.com;
    
    ssl_certificate /etc/letsencrypt/live/litellm.yourcompany.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/litellm.yourcompany.com/privkey.pem;
    
    # 强制 HTTPS
    add_header Strict-Transport-Security "max-age=31536000" always;
}

# HTTP 重定向
server {
    listen 80;
    server_name litellm.yourcompany.com;
    return 301 https://$server_name$request_uri;
}
```

---

## 🐛 常见问题和解决方案

### Q1: iframe 加载失败 - CORS 错误

**症状:**
```
Access to XMLHttpRequest blocked by CORS policy
```

**解决方案:**
```bash
# 修改 LiteLLM 环境变量
# 在 .env 或 docker-compose.yml 中
LITELLM_CORS_ORIGINS="https://your-wordpress-domain.com"

# 重启服务
docker compose restart litellm
```

### Q2: API Key 无法工作 - 401 Unauthorized

**症状:**
```
{"error": "Invalid authorization header"}
```

**解决方案:**
```bash
# 1. 验证 Master Key
curl -H "Authorization: Bearer sk-your-key" \
  http://localhost:24157/key/list

# 2. 检查 Key 状态
curl -H "Authorization: Bearer sk-your-key" \
  http://localhost:24157/key/info

# 3. 如果 Key 被禁用，重新激活
curl -X POST http://localhost:24157/key/unblock \
  -H "Authorization: Bearer sk-your-key" \
  -d '{"key": "sk-xxx"}'
```

### Q3: 数据库连接失败

**症状:**
```
ERROR: could not connect to server: Connection refused
```

**解决方案:**
```bash
# 1. 检查 PostgreSQL 容器状态
docker compose ps postgres

# 2. 查看 PostgreSQL 日志
docker compose logs postgres

# 3. 测试数据库连接
docker compose exec postgres psql -U litellm_user -d litellm_db -c "SELECT 1;"

# 4. 检查网络连接
docker compose exec litellm ping postgres

# 5. 重启 PostgreSQL
docker compose restart postgres
```

### Q4: 性能缓慢 - 高延迟

**症状:**
```
API 响应时间 > 5 秒
```

**解决方案:**
```bash
# 1. 检查 CPU 和内存使用
docker stats litellm

# 2. 启用 Redis 缓存
# 在 .env 中
REDIS_URL=redis://redis:6379

# 3. 优化数据库
docker compose exec postgres psql -U litellm_user -d litellm_db << EOF
CREATE INDEX idx_api_keys_user_id ON api_keys(user_id);
CREATE INDEX idx_logs_created_at ON api_logs(created_at);
VACUUM ANALYZE;
EOF

# 4. 增加 Docker 资源限制
# 在 docker-compose.yml 中
services:
  litellm:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G

# 5. 重启以应用更改
docker compose restart litellm
```

### Q5: 内存不足 - OOM Killer

**症状:**
```
Container killed due to OOM
```

**解决方案:**
```bash
# 1. 检查内存使用
free -h

# 2. 增加 Docker 内存限制
# 在 docker-compose.yml 中
services:
  litellm:
    deploy:
      resources:
        limits:
          memory: 6G
        reservations:
          memory: 4G

# 3. 启用交换（临时方案）
dd if=/dev/zero of=/swapfile bs=1G count=4
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# 4. 优化配置
# 减少缓存大小、日志级别等
```

---

## 📈 性能优化建议

### 1. 数据库优化

```sql
-- 创建必要的索引
CREATE INDEX idx_api_keys_user_id ON api_keys(user_id);
CREATE INDEX idx_api_keys_status ON api_keys(status);
CREATE INDEX idx_api_logs_created_at ON api_logs(created_at);
CREATE INDEX idx_api_logs_key_id ON api_logs(key_id);

-- 定期清理过期数据
DELETE FROM api_logs WHERE created_at < NOW() - INTERVAL '90 days';

-- 重建索引
REINDEX TABLE api_logs;
```

### 2. Redis 缓存优化

```bash
# 在 .env 中启用
REDIS_URL=redis://redis:6379
CACHE_TTL=3600  # 1小时缓存

# 监控 Redis
docker compose exec redis redis-cli info stats
docker compose exec redis redis-cli keys '*' | wc -l
```

### 3. 连接池优化

```yaml
# 在 litellm-config.yaml 中
general_settings:
  database_url: postgresql://litellm_user:pass@postgres:5432/litellm_db?pool_size=20&max_overflow=40
```

### 4. 日志优化

```yaml
# 不要在生产环境启用详细调试
logging:
  type: file
  log_dir: /app/logs
  log_level: INFO  # 改为 WARNING
```

---

## 🔄 备份和恢复

### 备份 PostgreSQL

```bash
# 完整备份
docker compose exec postgres pg_dump -U litellm_user litellm_db > backup.sql

# 压缩备份
docker compose exec postgres pg_dump -U litellm_user litellm_db | gzip > backup_$(date +%Y%m%d).sql.gz

# 定期备份（使用 cron）
0 2 * * * cd /opt/litellm-server && docker compose exec -T postgres pg_dump -U litellm_user litellm_db | gzip > /backup/litellm_$(date +\%Y\%m\%d).sql.gz
```

### 恢复数据库

```bash
# 从备份恢复
docker compose exec -T postgres psql -U litellm_user litellm_db < backup.sql

# 或使用 gzip 压缩文件
gunzip < backup.sql.gz | docker compose exec -T postgres psql -U litellm_user litellm_db
```

### 备份数据文件

```bash
# 备份所有 Docker 卷
tar -czf litellm-backup-$(date +%Y%m%d).tar.gz /opt/litellm-server

# 备份特定卷
docker run --rm -v litellm_server_postgres_data:/data -v $(pwd):/backup ubuntu tar czf /backup/postgres-backup.tar.gz -C /data .
```

---

## 📝 日志分析

### 查看各服务日志

```bash
# LiteLLM 日志
docker compose logs -f litellm

# PostgreSQL 日志
docker compose logs -f postgres

# 所有日志
docker compose logs -f

# 查看特定容器的最后 100 行
docker compose logs --tail=100 litellm
```

### 日志文件位置

```
/opt/litellm-server/logs/  # LiteLLM 应用日志
/var/log/docker/           # Docker 日志
/var/lib/docker/containers/*/  # 容器日志
```

### 分析 API 错误

```bash
# 查找所有 5xx 错误
docker compose logs litellm | grep "500"

# 查找 API 超时
docker compose logs litellm | grep "timeout"

# 查找认证失败
docker compose logs litellm | grep "unauthorized\|401"
```

---

## 🚀 升级指南

### 升级 LiteLLM 版本

```bash
# 1. 备份数据库
docker compose exec postgres pg_dump -U litellm_user litellm_db > backup_pre_upgrade.sql

# 2. 停止当前服务
docker compose down

# 3. 更新镜像
docker pull ghcr.io/berriai/litellm:main-latest

# 4. 启动新版本
docker compose up -d

# 5. 验证升级
curl http://localhost:24157/health

# 6. 检查日志
docker compose logs litellm
```

### 升级 WordPress 插件

```bash
# 1. 备份插件
tar -czf litellm-dashboard-backup.tar.gz /var/www/html/wp-content/plugins/litellm-dashboard/

# 2. 更新插件文件
cp -r new-plugin-files /var/www/html/wp-content/plugins/litellm-dashboard/

# 3. 在 WordPress 中验证
# - 登录后台
# - 检查插件是否正常工作
# - 测试 API 连接
```

---

## 📞 获取帮助

### 调试命令

```bash
# 完整系统诊断
docker compose ps
docker stats
docker compose logs
free -h
df -h

# 网络诊断
docker compose exec litellm ping postgres
docker compose exec litellm curl http://localhost:24157/health
netstat -tuln | grep 24157

# 数据库诊断
docker compose exec postgres psql -U litellm_user -d litellm_db -c "\dt"
docker compose exec postgres psql -U litellm_user -d litellm_db -c "SELECT COUNT(*) FROM api_keys;"
```

### 收集支持信息

```bash
# 生成诊断报告
cat > /tmp/litellm-diagnostics.sh << 'EOF'
echo "=== System Info ==="
uname -a
free -h
df -h

echo "=== Docker Info ==="
docker compose ps
docker stats --no-stream

echo "=== LiteLLM Logs (Last 50 lines) ==="
docker compose logs --tail=50 litellm

echo "=== Database Info ==="
docker compose exec postgres psql -U litellm_user -d litellm_db -c "SELECT COUNT(*) FROM api_keys;"

echo "=== Network Test ==="
curl -v http://localhost:24157/health
EOF

chmod +x /tmp/litellm-diagnostics.sh
/tmp/litellm-diagnostics.sh > /tmp/diagnostics-report.txt
```

---

## 📚 参考资源

- **LiteLLM 官方文档**: https://docs.litellm.ai
- **GitHub 仓库**: https://github.com/BerriAI/litellm
- **Docker 文档**: https://docs.docker.com
- **PostgreSQL 文档**: https://www.postgresql.org/docs
- **WordPress 插件开发**: https://developer.wordpress.org/plugins

