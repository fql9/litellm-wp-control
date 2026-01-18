# LiteLLM 部署（Docker Compose，生产基线）

> [< 上一篇：同机部署网络拓扑](03-同机部署网络拓扑.md) | [返回目录](README.md) | [下一篇：WordPress 集成 >](05-WordPress-集成（企业级要点）.md)

> 文档默认 LiteLLM 版本：**v1.80.11-stable**（更新日期：**2026-01-13**）

## 目录结构建议

- `/opt/litellm-server/`
  - `docker-compose.yml`
  - `.env`（`chmod 600`）
  - `config/litellm-config.yaml`
  - `logs/`
  - `data/`

## 推荐部署方式（使用本仓库脚本）

在本仓库目录执行：

```bash
sudo bash scripts/deploy-full.sh \
  --install-deps \
  --litellm-image ghcr.io/berriai/litellm:v1.80.11-stable
```

脚本会做的事（你需要知道这些文件落在哪）：

- 生成/准备 `/opt/litellm-server/`（compose/config）
- 生成或补齐 `/opt/litellm-server/.env`（默认权限 600）
- 启动 LiteLLM + PostgreSQL + Redis

## 模板文件

- **核心 Compose**：`../docker-compose.core.yml`（复制为 `docker-compose.yml`）
- **环境变量示例**：`../env.example`（复制为 `.env`）
- **LiteLLM 配置模板**：`../config/litellm-config.yaml`

## 需要你手工确认/调整的配置（强烈建议逐条完成）

### 1) `.env`（敏感信息）

文件位置：`/opt/litellm-server/.env`

你至少需要确认：

- `LITELLM_MASTER_KEY`：运维 bootstrap 用（不要写入 WP 数据库/不要暴露到浏览器）
- `OPENAI_API_KEY` / `ANTHROPIC_API_KEY`：按你启用的上游模型提供方填写
- `POSTGRES_PASSWORD`：已自动生成也建议纳入密钥管理

权限建议：

```bash
chmod 600 /opt/litellm-server/.env
```

### 2) `config/litellm-config.yaml`（模型列表）

文件位置：`/opt/litellm-server/config/litellm-config.yaml`

你需要按实际业务修改：

- `model_list[].model_name`：对外暴露给调用方的模型名（例如 `gpt-4`）
- `litellm_params.model`：真实上游模型（例如 `openai/gpt-4-turbo`）

修改后重载：

```bash
cd /opt/litellm-server
docker compose up -d
```

## 版本锁定（强制）

在 `.env` 中设置：

- `LITELLM_IMAGE=ghcr.io/berriai/litellm:v1.80.11-stable`（文档默认版本：2026-01-13）

版本来源建议参考官方仓库：[BerriAI/litellm](https://github.com/BerriAI/litellm)

## 启动命令

```bash
cd /opt/litellm-server
chmod 600 .env
docker compose up -d
docker compose ps
curl -fsS http://127.0.0.1:24157/health/liveliness
```

> 说明：v1.80+ 某些端点可能需要鉴权；因此本文默认使用通常不需要鉴权的 `/health/liveliness`。

## 常用运维命令（上线后常用）

```bash
cd /opt/litellm-server

# 查看容器状态
docker compose ps

# 查看 LiteLLM 日志
docker compose logs -f litellm

# 查看数据库日志
docker compose logs -f postgres

# 重启 LiteLLM
docker compose restart litellm
```

## Key 治理（企业强制：Master Key 只用于 bootstrap）

1) Master Key（`LITELLM_MASTER_KEY`）只给运维，不写入 WordPress 数据库、不出现在浏览器。
2) 用 Master Key 生成一个 **service key**（可给 WordPress 后端或企业内部管理服务使用），用于创建/管理业务 key。

推荐（使用本仓库脚本生成/获取，并写入 `/opt/litellm-server/service-key.txt`）：

```bash
sudo bash scripts/deploy-full.sh --service-key
```

## UI 登录（用户名/密码）与对外基址（避免 https -> http）

> LiteLLM UI 的登录与重定向行为会随版本/是否启用 SSO 不同而变化。生产推荐明确设置 UI 登录账户，并配置对外基址。

1) 在 `/opt/litellm-server/.env` 添加（或修改）：

```bash
UI_USERNAME=your_admin_username
UI_PASSWORD=your_strong_password
PROXY_BASE_URL=https://litellm.example.com
```

2) 重启 LiteLLM 使环境变量生效：

```bash
cd /opt/litellm-server
docker compose up -d
```

3) 访问：`https://litellm.example.com/ui/login/`，使用 `UI_USERNAME`/`UI_PASSWORD` 登录。

参考官方文档：
- UI 登录配置：[LiteLLM UI](https://docs.litellm.ai/docs/proxy/ui?utm_source=openai)
- virtual/service keys：[Virtual Keys](https://docs.litellm.ai/docs/proxy/virtual_keys?utm_source=openai)

## 升级/回滚（简版说明）

- 升级核心步骤：修改 `/opt/litellm-server/.env` 中的 `LITELLM_IMAGE`（先在预生产验收）
- 重新拉取并重建：

```bash
cd /opt/litellm-server
docker compose pull
docker compose up -d
```

完整的备份/升级/回滚流程见：`08-运维（备份-升级-回滚）.md`

## （可选）开发/调试模式（参考官方仓库）

如果你需要对 LiteLLM 做二次开发或排查 UI/后端问题，可以参考官方仓库的开发模式说明（例如在本机启动依赖服务、启动 proxy 后端与 dashboard 前端）。详见：[BerriAI/litellm](https://github.com/BerriAI/litellm)
