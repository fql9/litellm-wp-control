# WordPress 集成（企业级要点）

> [< 上一篇：LiteLLM 部署](04-LiteLLM-部署（Docker-Compose）.md) | [返回目录](README.md) | [下一篇：观测与告警 >](06-观测与告警（Prometheus-Grafana）.md)

> 文档默认 LiteLLM 版本：**v1.80.11**（更新日期：**2026-01-13**）

本章目标：在 **WordPress 后台（HTTPS）** 中完成 LiteLLM 的“可视化（iframe `/ui`）+ 管理调用（PHP 服务器端）”集成，同时满足企业最基本的密钥与暴露面要求。

---

## A. 先明确几个硬约束（避免踩坑）

### A1) WordPress 后台是 HTTPS → LiteLLM `/ui` 也必须是 HTTPS

如果你的 WP 后台是 `https://agent.xooer.com`，那么 iframe 里的 LiteLLM `/ui` **也必须**通过 `https://` 访问，否则浏览器会以 **mixed content** 直接拦截（与 CSP/CORS 无关）。

### A2) LiteLLM 端口不对公网暴露（强制）

本仓库默认 LiteLLM 仅绑定 `127.0.0.1:24157`，外网不可直连；对外统一通过 **宿主机 Nginx/Apache 反代 + HTTPS**。

### A3) 通配符证书（必须确认覆盖范围）

- 若你的通配符证书为 `*.xooer.com`：推荐 LiteLLM 子域名用 `litellm.xooer.com`（✅覆盖）
- 若你想用 `litellm.agent.xooer.com`：需要 `*.agent.xooer.com`（`*.xooer.com` ❌不覆盖二级子域）

---

## B. 准备 LiteLLM 的 HTTPS 子域名入口（反代）

> 你需要：1) DNS 解析 2) Nginx/Apache 虚拟主机 3) 通配符证书文件路径。

### B1) DNS

为 LiteLLM 子域名加一条 A 记录：

- `litellm.xooer.com` → 指向 LiteLLM 服务器公网 IP

### B2) Nginx 配置（通配符证书 + iframe 允许）

仓库提供模板：`../nginx/litellm.conf`。你需要按你的环境替换：

- `server_name litellm.yourcompany.com;` → `litellm.xooer.com`
- `ssl_certificate /path/to/wildcard/fullchain.pem;` → 你的证书链文件
- `ssl_certificate_key /path/to/wildcard/privkey.pem;` → 你的私钥文件
- `frame-ancestors ... https://your-wordpress-domain.com` → `https://agent.xooer.com`

建议落地路径（Ubuntu/Nginx 默认习惯）：

1) 复制到站点：
- `/etc/nginx/sites-available/litellm.conf`
2) 启用：
- `ln -s /etc/nginx/sites-available/litellm.conf /etc/nginx/sites-enabled/litellm.conf`
3) 校验并 reload：
- `nginx -t && systemctl reload nginx`

### B3) （强烈推荐）同机自环解析，避免“访问公网再回环”

由于 WordPress 与 LiteLLM 在同机，建议在服务器 `/etc/hosts` 里加：

- `127.0.0.1  litellm.xooer.com`

这样 WordPress 的 **服务器端调用**（PHP）会走本机回环 → Nginx → LiteLLM，不依赖公网回环/NAT。

---

## C. 生成并保存 service key（给 WordPress 后端使用）

### C1) 为什么不用 Master Key

- Master Key 只用于运维 bootstrap（生成/吊销 key、排障）
- WordPress 侧只使用一个“管理用途的 service key”（权限收敛、可轮换、可吊销）

### C2) 生成/获取命令（本仓库脚本）

在 LiteLLM 服务器执行：

```bash
sudo bash scripts/deploy-full.sh --service-key
sudo cat /opt/litellm-server/service-key.txt
```

> 该文件默认权限为 600，仅 root 可读。企业实践中你可以把它纳入密钥管理系统（Vault/KMS/堡垒机下发）。

---

## D. 部署 WordPress 插件（示例）并完成配置

> 插件目录在：`../wordpress-plugin/litellm-dashboard/`（示例/POC）。你可以直接使用，也可以基于它做企业加固（二次开发）。

### D1) 安装插件（两种方式）

- 方式 1（推荐）：把 `litellm-dashboard/` 目录复制到：
  - `wp-content/plugins/litellm-dashboard/`
  - 然后在 WP 后台 → **插件** → 启用 **LiteLLM Dashboard**
- 方式 2（后台上传）：把 `litellm-dashboard/` 压成 `litellm-dashboard.zip`（注意 zip 根目录必须是 `litellm-dashboard/`），后台上传安装。

### D2) 配置方式（企业推荐：常量注入，避免密钥落库）

在 `wp-config.php` 中加入（放在 “stop editing” 之前）：

```php
define('LITELLM_API_BASE', 'https://litellm.xooer.com');
define('LITELLM_SERVICE_KEY', 'sk-xxxxx'); // 取自 /opt/litellm-server/service-key.txt
```

然后进入 WP 后台 → **LiteLLM** → **设置**：

- 你会看到 `API 基础 URL` 变成只读（说明已成功从常量读取）
- service key 输入框会提示“由常量注入”（无需在页面里保存密钥）

---

## E. 验证清单（按顺序排查）

### E1) 反代与证书

在任意机器执行：

- `curl -I https://litellm.xooer.com/ui/ | egrep -i \"content-security-policy|x-frame-options\"`

期望：
- 有 `Content-Security-Policy: frame-ancestors ... https://agent.xooer.com`
- 没有 `X-Frame-Options: DENY/SAMEORIGIN`

### E2) LiteLLM 健康

在 LiteLLM 服务器：

- `curl -fsS http://127.0.0.1:24157/health`

### E3) WordPress 后台

- WP 后台打开 **LiteLLM Dashboard** 页面
- iframe 能加载 LiteLLM `/ui`（不报 mixed content/拒绝嵌入）

---

## F. 生产加固建议（强烈建议落地）

- **限制管理面访问**：`/ui`、`/key/*`、`/api/*` 建议仅 VPN/堡垒机/IP 白名单访问（或接入 SSO）
- **service key 轮换**：定期轮换，变更需审计；不落库（仅 `wp-config.php` / 环境变量 / 密钥管理系统）
- **最小权限**：service key 的模型、预算、rpm 限制按你的组织策略收敛

## 示例插件（仅供参考）

- 插件代码：`../wordpress-plugin/litellm-dashboard/`

你可以作为起点，但生产需按上述原则加固（尤其是权限、审计、密钥管理与访问控制）。

