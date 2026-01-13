# WordPress 集成（企业级要点）

## 核心原则（强制）

- **最小权限**：WordPress 使用 LiteLLM 的 **service key**（而不是 master key）
- **密钥不落库**：禁止把 master/service key 明文写入 `wp_options`
- **服务器端调用**：管理接口尽量由 PHP 在服务端调用，避免 token 泄露到浏览器
- **权限与审计**：对“创建/禁用/删除 key”等操作做权限隔离与审计记录

## 推荐实现方式

### 1) service key 注入方式

推荐顺序：

1. 写入 `wp-config.php` 常量（文件权限收紧）
2. 由 systemd / PHP-FPM 环境变量注入
3. （不推荐）写入 WP 数据库 option（除非加密 + 严格权限 + 审计）

### 2) iframe 嵌入 LiteLLM `/ui`

要点：
- 通过宿主机反代域名访问 `/ui`
- 由反代层配置 `Content-Security-Policy: frame-ancestors https://<your-wordpress-domain>`
- 必要时在反代层隐藏上游 `X-Frame-Options`

参考模板：`../nginx/litellm.conf`

## 示例插件（仅供参考）

原文档中包含一份示例插件代码（偏 POC），已抽取到仓库目录：

- `../wordpress-plugin/litellm-dashboard/`

你可以作为起点，但生产需按上述强制原则加固。

