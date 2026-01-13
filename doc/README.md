# 文档目录

本目录为 `litellm-wp-control` 的文档中心（按章节拆分）。

## 目录

- `00-快速上手.md`
- `01-系统架构.md`
- `02-版本选择与锁定.md`
- `03-同机部署网络拓扑.md`
- `04-LiteLLM-部署（Docker-Compose）.md`
- `05-WordPress-集成（企业级要点）.md`
- `06-观测与告警（Prometheus-Grafana）.md`
- `07-安全基线（强制项）.md`
- `08-运维（备份-升级-回滚）.md`
- `09-故障排查.md`

## 代码/模板位置

- **核心部署 Compose**：`../docker-compose.core.yml`（落地时复制为 `/opt/litellm-server/docker-compose.yml`）
- **观测栈 Compose**：`../docker-compose.observability.yml`
- **LiteLLM 配置模板**：`../config/litellm-config.yaml`
- **环境变量示例**：`../env.example`（落地时复制为 `.env` 并 `chmod 600`）
- **宿主机 Nginx 反代示例**：`../nginx/litellm.conf`
- **Prometheus 配置/规则**：`../observability/prometheus/`
- **Alertmanager 配置**：`../observability/alertmanager/`

