# LiteLLM 部署（Docker Compose，生产基线）

## 目录结构建议

- `/opt/litellm-server/`
  - `docker-compose.yml`
  - `.env`（`chmod 600`）
  - `config/litellm-config.yaml`
  - `logs/`
  - `data/`

## 模板文件

- **核心 Compose**：`../docker-compose.core.yml`（复制为 `docker-compose.yml`）
- **环境变量示例**：`../env.example`（复制为 `.env`）
- **LiteLLM 配置模板**：`../config/litellm-config.yaml`

## 启动命令

```bash
cd /opt/litellm-server
chmod 600 .env
docker compose up -d
docker compose ps
curl -fsS http://127.0.0.1:24157/health
```

## Key 治理（企业强制：Master Key 只用于 bootstrap）

1) Master Key（`LITELLM_MASTER_KEY`）只给运维，不写入 WordPress 数据库、不出现在浏览器。
2) 用 Master Key 生成一个 **WordPress 专用 service key**，WordPress 后端使用它来创建/管理业务 key。

> 生成命令参考：在 `litellm-wordpress-deploy.md` 中的“用 Master Key 生成 WordPress 专用 service key”示例。

