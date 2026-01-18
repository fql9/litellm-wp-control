# litellm-wp-control

同一台服务器上实现 **LiteLLM（Docker）** 与 **WordPress（Ubuntu 原生）** 的企业级集成：在 WordPress 后台完成 **Key 管理、监控展示、可视化呈现（iframe 嵌入 LiteLLM `/ui`）**，并提供可落地的部署脚本与配置模板。

> 文档默认 LiteLLM 版本：**v1.80.11-stable**（更新日期：**2026-01-13**）

## 适用场景

- 你希望把 LiteLLM 作为企业内部统一的 LLM 网关入口
- 你希望用 WordPress 作为管理门户（控制 + 监控 + 可视化）
- 你要求生产级：版本可控、暴露面可控、安全基线可落地

## 你会得到什么（结果清单）

- **LiteLLM 网关**：统一 OpenAI-compatible API 入口（路由/日志/用量/成本/Key）
- **LiteLLM 原生 UI**：通过 `https://litellm.<domain>/ui/` 访问（可被 WP 后台 iframe 嵌入）
- **WordPress 插件（示例/POC）**：后台页面、iframe 嵌入、以及通过 WP 服务端调用 LiteLLM 管理接口

## 项目结构

- `doc/`：按章节拆分的文档（推荐从这里读）
- `wordpress-plugin/`：WordPress 插件示例代码（可直接复制到 `wp-content/plugins/`）
- `docker-compose.core.yml`：核心服务模板（Postgres/Redis/LiteLLM，LiteLLM 仅绑定 `127.0.0.1:24157`）
- `config/litellm-config.yaml`：LiteLLM 配置模板
- `env.example`：环境变量示例（复制为 `.env`）
- `nginx/litellm.conf`：宿主机 Nginx 反代示例（含 iframe 所需 CSP）
- `scripts/deploy-full.sh`：一键部署 LiteLLM 脚本

## 关键端口（默认全内网/本机）

- LiteLLM：`127.0.0.1:24157`

## 快速开始（以 `https://wp.example.com` 为例：WordPress 后台 HTTPS + LiteLLM 子域名 HTTPS）

如果你的 WordPress 后台是 `https://wp.example.com`，且希望后台 iframe 嵌入 LiteLLM `/ui`，则 LiteLLM 对外入口也必须是 HTTPS（否则浏览器 mixed content 拦截）。

> 说明：部署脚本只负责 LiteLLM（Docker）部署，不负责 Nginx/证书/WordPress 插件安装；这些步骤由你按本文与 `doc/` 完成。

前置条件：

- 你有 root/sudo 权限
- 服务器可联网安装依赖（若使用 `--install-deps`）
- DNS 已将 `litellm.example.com` 指向本机公网 IP（或你选择的子域名）
- 你有可用的通配符证书（例如 `*.example.com`）并知道证书文件路径

### 1) 部署 LiteLLM

```bash
sudo bash scripts/deploy-full.sh \
  --install-deps \
  --litellm-image ghcr.io/berriai/litellm:v1.80.11-stable
```

验证：

```bash
curl -fsS http://127.0.0.1:24157/health/liveliness
```

### 2) 生成/获取 service key（给 WordPress 后端用）

```bash
sudo bash scripts/deploy-full.sh --service-key
sudo cat /opt/litellm-server/service-key.txt
```

### 3) 配置 Nginx：`https://litellm.example.com` → `http://127.0.0.1:24157`

1) 安装 Nginx（若未安装）：

```bash
sudo apt-get update
sudo apt-get install -y nginx
sudo systemctl enable --now nginx
```

2) 使用模板配置站点（替换域名、证书路径、frame-ancestors）：

```bash
sudo cp nginx/litellm.conf /etc/nginx/sites-available/litellm.conf
sudo ln -sf /etc/nginx/sites-available/litellm.conf /etc/nginx/sites-enabled/litellm.conf
sudo nginx -t
sudo systemctl reload nginx
```

> 你需要把模板里 `litellm.yourcompany.com`、证书路径、以及 `https://your-wordpress-domain.com` 替换为你们的真实值（例如 `https://wp.example.com`）。

3) （推荐）同机自环解析，避免访问公网回环：

```bash
echo '127.0.0.1 litellm.example.com' | sudo tee -a /etc/hosts
```

### 4) 部署 WordPress 插件并配置（不落库）

1) 安装插件：
- 复制 `wordpress-plugin/litellm-dashboard/` 到 `wp-content/plugins/litellm-dashboard/`
- WP 后台 → **插件** → 启用 **LiteLLM Dashboard**

2) 推荐配置（写入 `wp-config.php` 常量）：

```php
define('LITELLM_API_BASE', 'https://litellm.example.com');
define('LITELLM_SERVICE_KEY', 'sk-xxxxx'); // 取自 /opt/litellm-server/service-key.txt
```

### 5) 最终验收

- 直接访问 UI：`https://litellm.example.com/ui/`
- WordPress 后台打开 LiteLLM 页面：iframe 正常加载（无 mixed content / refused to frame）

---

## 版本与官方参考

- LiteLLM 官方仓库（功能/发布/变更）：[BerriAI/litellm](https://github.com/BerriAI/litellm)
- 本仓库默认固定版本：`v1.80.11-stable`（2026-01-13）

## 文档入口

- 文档目录：`doc/README.md`
- 建议阅读顺序：`doc/00-快速上手.md` → `doc/05-WordPress-集成（企业级要点）.md` → `doc/07-安全基线（强制项）.md` → `doc/09-故障排查.md`

