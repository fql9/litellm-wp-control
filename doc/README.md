# 文档中心

本目录为 `litellm-wp-control` 的详细文档（按章节拆分）。

> 文档默认 LiteLLM 版本：**v1.80.11-stable**（更新日期：**2026-01-13**）

## 📚 目录

### 🚀 入门
- [00-快速上手.md](00-快速上手.md)：完整链路快速上手（WordPress HTTPS + LiteLLM + HTTPS 子域名 + 插件）。
- [01-系统架构.md](01-系统架构.md)：了解 WordPress + LiteLLM 的组件与数据流。

### 🏗️ 部署与集成
- [02-版本选择与锁定.md](02-版本选择与锁定.md)：**企业强制**。避免使用 `main-latest`，确保生产稳定。
- [03-同机部署网络拓扑.md](03-同机部署网络拓扑.md)：网络端口规划，缩小攻击面。
- [04-LiteLLM-部署（Docker-Compose）.md](04-LiteLLM-部署（Docker-Compose）.md)：核心服务的详细部署说明。
- [05-WordPress-集成（企业级要点）.md](05-WordPress-集成（企业级要点）.md)：Service Key 管理、iframe 嵌入与权限控制。

### 🛡️ 运维与安全
- [07-安全基线（强制项）.md](07-安全基线（强制项）.md)：**强制**。网络、密钥与反代的安全配置。
- [08-运维（备份-升级-回滚）.md](08-运维（备份-升级-回滚）.md)：生产环境的日常运维操作。
- [09-故障排查.md](09-故障排查.md)：常见问题（iframe 加载失败、401、反代问题）排查。

## 📂 代码/模板位置索引

- **核心部署 Compose**：`../docker-compose.core.yml`
- **LiteLLM 配置模板**：`../config/litellm-config.yaml`
- **环境变量示例**：`../env.example`
- **Nginx 反代示例**：`../nginx/litellm.conf`
- **一键脚本**：`../scripts/deploy-full.sh`
