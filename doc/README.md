# 文档中心

本目录为 `litellm-wp-control` 的详细文档（按章节拆分）。

## 📚 目录

### 🚀 入门
- [00-快速上手.md](00-快速上手.md)：部署 LiteLLM（Docker + 观测 + service key，一条命令 + 安全默认 + 自动化）。
- [01-系统架构.md](01-系统架构.md)：了解 WordPress + LiteLLM + 观测栈的组件与数据流。

### 🏗️ 部署与集成
- [02-版本选择与锁定.md](02-版本选择与锁定.md)：**企业强制**。避免使用 `main-latest`，确保生产稳定。
- [03-同机部署网络拓扑.md](03-同机部署网络拓扑.md)：网络端口规划，缩小攻击面。
- [04-LiteLLM-部署（Docker-Compose）.md](04-LiteLLM-部署（Docker-Compose）.md)：核心服务的详细部署说明。
- [05-WordPress-集成（企业级要点）.md](05-WordPress-集成（企业级要点）.md)：Service Key 管理、iframe 嵌入与权限控制。

### 🛡️ 运维与安全
- [06-观测与告警（Prometheus-Grafana）.md](06-观测与告警（Prometheus-Grafana）.md)：全链路监控配置。
- [07-安全基线（强制项）.md](07-安全基线（强制项）.md)：**强制**。网络、密钥与反代的安全配置。
- [08-运维（备份-升级-回滚）.md](08-运维（备份-升级-回滚）.md)：生产环境的日常运维操作。
- [09-故障排查.md](09-故障排查.md)：常见问题（iframe 加载失败、401、无指标）排查。

## 📂 代码/模板位置索引

- **核心部署 Compose**：`../docker-compose.core.yml`
- **观测栈 Compose**：`../docker-compose.observability.yml`
- **LiteLLM 配置模板**：`../config/litellm-config.yaml`
- **环境变量示例**：`../env.example`
- **Nginx 反代示例**：`../nginx/litellm.conf`
- **监控配置**：`../observability/`
- **全功能一键脚本**：`../scripts/deploy-full.sh`
