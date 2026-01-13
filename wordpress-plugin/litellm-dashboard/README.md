# LiteLLM Dashboard（WordPress 插件示例）

> 本目录为从文档中抽取出来的 **示例插件代码（偏 POC）**，用于演示在 WordPress 后台集成 LiteLLM 的仪表盘、Key 管理与 iframe 嵌入 `/ui`。

## 安装

1. 将 `litellm-dashboard/` 复制到你的 WordPress：`wp-content/plugins/litellm-dashboard/`
2. WordPress 后台 → **插件** → 启用 **LiteLLM Dashboard**

## 配置

- WordPress 后台 → **LiteLLM** → **设置**
  - **API 基础 URL**：例如 `http://127.0.0.1:24157`（同机回环）或 `http://litellm.yourcompany.com`（反代域名）
  - **密钥**：建议使用 LiteLLM 的 **WordPress 专用 service key**（不要使用 Master Key）

## 重要安全说明（生产必读）

当前示例插件 **支持** 通过 `wp-config.php` 常量注入（推荐），避免密钥落库：

- `define('LITELLM_API_BASE', 'http://litellm.yourcompany.com');`
- `define('LITELLM_SERVICE_KEY', 'sk-...');`

service key 获取方式（本仓库脚本提供指令）：

- `sudo bash scripts/deploy-full.sh --service-key`

若不使用常量注入而选择在后台表单里填写，则会把密钥保存到 WordPress option（`litellm_settings.master_key`）。这在企业生产环境通常 **不合规**。

企业落地建议：
- **Master Key 只用于运维 bootstrap**，从不写入 WP 数据库
- WordPress 使用 **service key** 并通过 `wp-config.php` 常量或系统环境变量注入（不落库）
- 为插件定义独立 capability，并对 key 变更做审计日志

## 代码结构

- `litellm-dashboard.php`：插件主文件（菜单、页面、AJAX、资源加载）
- `assets/css/admin-style.css`：后台样式
- `assets/js/admin-script.js`：后台交互与图表

