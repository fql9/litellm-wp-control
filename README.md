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

## 全功能完整部署（推荐：几条命令完成）

> 目标：WordPress 原生 + LiteLLM Docker + Nginx HTTPS + 观测栈 + 插件。  
> 安全默认：LiteLLM 仅绑定 `127.0.0.1:24157`；版本强制锁定（不允许滚动 tag）；支持将 service key 注入 `wp-config.php`（避免密钥落库）。

前置条件（建议先确认）：

- 服务器已安装并运行 WordPress（原生）
- DNS 已将 `litellm.<你的域名>` 指向本服务器公网 IP（若启用 `--enable-tls`）
- 80/443 对外可达（若启用 `--enable-tls`）
- 你有 root/sudo 权限

在本仓库目录执行（示例参数）：

```bash
sudo bash scripts/deploy-full.sh \
  --install-deps \
  --litellm-domain litellm.example.com \
  --wp-domain wp.example.com \
  --email admin@example.com \
  --litellm-image ghcr.io/berriai/litellm:vX.Y.Z \
  --enable-tls \
  --configure-wp-config
```

> 提示：`vX.Y.Z` 需要替换为你要锁定的真实版本（建议从官方 Releases 选择稳定版）。

脚本会自动完成：复制/生成 `/opt/litellm-server`、配置 Nginx 反代、申请 HTTPS（可选）、启动 LiteLLM 与观测栈、部署插件、生成 WordPress service key。

> 版本来源请参考 LiteLLM 官方仓库：[BerriAI/litellm](https://github.com/BerriAI/litellm)

脚本帮助：`sudo bash scripts/deploy-full.sh --help`

## 文档入口

- 文档目录：`doc/README.md`
- 建议阅读顺序：`doc/00-快速上手.md` → `doc/07-安全基线（强制项）.md` → `doc/06-观测与告警（Prometheus-Grafana）.md`

