# litellm-wp-control

同一台服务器上实现 **LiteLLM（Docker）** 与 **WordPress（Ubuntu 原生）** 的企业级集成：在 WordPress 后台完成 **Key 管理、监控展示、可视化呈现（iframe 嵌入 LiteLLM `/ui`）**，并提供 **Prometheus/Grafana/Alertmanager** 的观测与告警模板。

## 适用场景

- 你希望把 LiteLLM 作为企业内部统一的 LLM 网关入口
- 你希望用 WordPress 作为管理门户（控制 + 监控 + 可视化）
- 你要求生产级：版本可控、暴露面可控、可观测、可告警

## 项目结构

- `doc/`：按章节拆分的文档（推荐从这里读）
- `wordpress-plugin/`：WordPress 插件示例代码（可直接复制到 `wp-content/plugins/`）
- `docker-compose.core.yml`：核心服务模板（Postgres/Redis/LiteLLM，LiteLLM 仅绑定 `127.0.0.1:24157`）
- `docker-compose.observability.yml`：观测栈模板（Prometheus/Grafana/Alertmanager/node_exporter/cAdvisor/blackbox）
- `config/litellm-config.yaml`：LiteLLM 配置模板
- `env.example`：环境变量示例（复制为 `.env`）
- `nginx/litellm.conf`：宿主机 Nginx 反代示例（含 iframe 所需 CSP）
- `observability/`：Prometheus/Alertmanager/Grafana provisioning 等配置

## 3 分钟快速上手（核心服务）

> 生产基线：LiteLLM 不对公网暴露端口，只绑定回环；对外统一用宿主机 Nginx/Apache 反代与 HTTPS。

1) 拷贝模板到服务器（示例：`/opt/litellm-server`）

- 复制 `docker-compose.core.yml` 为 `/opt/litellm-server/docker-compose.yml`
- 复制 `env.example` 为 `/opt/litellm-server/.env`
- 复制 `config/litellm-config.yaml` 为 `/opt/litellm-server/config/litellm-config.yaml`

2) 修改 `/opt/litellm-server/.env` 并收紧权限

```bash
cd /opt/litellm-server
chmod 600 .env
```

3) 启动

```bash
docker compose up -d
docker compose ps
curl -fsS http://127.0.0.1:24157/health
```

## 5 分钟补齐观测（推荐）

```bash
cd /opt/litellm-server
docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d
curl -fsS http://127.0.0.1:9090/-/healthy
curl -fsS http://127.0.0.1:3000/api/health
curl -fsS http://127.0.0.1:9093/-/healthy
```

## 文档入口

- 文档目录：`doc/README.md`
- 建议阅读顺序：`doc/00-快速上手.md` → `doc/07-安全基线（强制项）.md` → `doc/06-观测与告警（Prometheus-Grafana）.md`

