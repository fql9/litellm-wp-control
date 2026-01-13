# LiteLLM + WordPress 企业级落地部署方案（入口）

本文档已拆分到 `doc/` 目录（按章节维护），并把关键代码/模板抽成独立文件（便于直接落地与复用）。

## 从这里开始

- `doc/README.md`（文档目录）
- `doc/00-快速上手.md`（最短启动路径）

## 关键默认端口（已避免使用 24157）

- LiteLLM 默认绑定：`127.0.0.1:24157`


---

## 📋 目录

1. [系统架构](#系统架构)
2. [硬件要求](#硬件要求)
3. [版本选择与锁定策略](#版本选择与锁定策略)
4. [生产网络拓扑（同机部署）](#生产网络拓扑同机部署)
5. [第一部分：LiteLLM 生产部署（Docker Compose）](#第一部分litellm-生产部署docker-compose)
6. [第二部分：WordPress 侧集成（企业级插件设计要点）](#第二部分wordpress-侧集成企业级插件设计要点)
7. [第三部分：观测与告警（Prometheus/Grafana/日志）](#第三部分观测与告警prometheusgrafana日志)
8. [第四部分：安全基线（强制项）](#第四部分安全基线强制项)
9. [第五部分：完整集成步骤](#第五部分完整集成步骤)
10. [第六部分：故障排查](#第六部分故障排查)
11. [检查清单](#检查清单)

---

## 系统架构

```
┌─────────────────────────────────────────────────────────────────┐
│                     WordPress 前端                               │
│  (API Key 管理 | 监控面板 | 权限控制)                               │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     │ HTTP/HTTPS
                     │ (REST API)
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                  LiteLLM Proxy Service                           │
│  (端口 24157)                                                      │
│  - 模型路由管理                                                    │
│  - API Key 验证                                                   │
│  - 使用情况追踪                                                    │
│  - 内置 Web UI (端口 24157/ui)                                      │
└────────────────────┬────────────────────────────────────────────┘
                     │
                ┌────┴────┬────────────────┬─────────┐
                ▼         ▼                ▼         ▼
            ┌────────┐ ┌────────┐    ┌────────┐ ┌────────┐
            │PostgreSQL│ │Redis │    │外部API  │ │监控系统 │
            │(数据库) │ │(缓存) │    │(OpenAI)│ │(Prom)  │
            └────────┘ └────────┘    └────────┘ └────────┘
```

---

## 硬件要求

| 项目 | 要求 |
|------|------|
| **CPU** | 4核以上 |
| **内存** | 8GB 最小（推荐16GB） |
| **磁盘** | 50GB SSD 最小 |
| **网络** | 100Mbps 以上 |
| **操作系统** | Ubuntu 20.04+ / CentOS 8+ |

---

## 版本选择与锁定策略

企业落地 **必须锁定 LiteLLM 版本**，禁止使用 `main-latest` 这类滚动 tag（接口/行为不可控）。

### 选择原则（由你的目标决定）
- **如果只需要**：OpenAI 兼容代理 + `/ui` + Key 管理 + PostgreSQL 落库 → 选择一个稳定发布版（语义化版本）并锁定
- **如果需要更强治理**：团队/配额/审计/更丰富指标 → 先在预生产验证接口与数据结构再锁定

### 锁定方式（强制）
- **镜像 tag 锁定**：例如 `ghcr.io/berriai/litellm:vX.Y.Z`
- **更强锁定（可选）**：生产用镜像 digest 锁定（避免同 tag 被重写；digest 不建议写在公开文档里，写在内部配置仓库/工单）

### 上线前验收（必须）
- `/health` 正常
- `/v1/chat/completions`（或你实际使用的 endpoints）成功返回
- `/key/generate`、`/key/list`、`/key/block`、`/key/delete` 可用
- `/metrics`（若启用）可被 Prometheus 抓取
- `/ui` 可访问（若要被 WordPress iframe 嵌入，需额外验证安全头策略）

---

## 生产网络拓扑（同机部署）

你的约束：WordPress 原生跑在 Ubuntu；LiteLLM 用 Docker。企业推荐拓扑如下：

- **LiteLLM 仅绑定本机回环**：`127.0.0.1:24157`（通过 `127.0.0.1:24157:24157` 端口映射实现）
  - 好处：外网不可直连 24157；WordPress（同机）可用 `http://127.0.0.1:24157` 做服务器端调用
- **对外统一入口**：宿主机 Nginx/Apache 反向代理到 `127.0.0.1:24157`，并提供 `https://litellm.example.com`
- **数据库/Redis 不暴露宿主机端口**：只在 Docker 私有网络中互通

> 重要：WordPress 插件对 LiteLLM 的“管理接口”调用应尽量走 **服务器端（PHP）**，不要让浏览器端直接拿到管理 token。

---

## 第一部分：LiteLLM 生产部署（Docker Compose）

### 步骤 1：服务器初始化

```bash
# 连接到服务器
ssh root@your-server-ip

# 更新系统
apt update && apt upgrade -y

# 安装必要工具
apt install -y \
  curl \
  wget \
  git \
  htop \
  vim \
  docker.io \
  docker-compose-plugin \
  postgresql-client

# 启动 Docker
systemctl start docker
systemctl enable docker

# 验证 Docker 安装
docker --version
docker compose version
```

### 步骤 2：创建项目目录结构

```bash
# 创建项目根目录
mkdir -p /opt/litellm-server
cd /opt/litellm-server

# 创建子目录
mkdir -p config logs data backups observability/prometheus observability/alertmanager observability/grafana

# 设置权限
chmod -R 755 /opt/litellm-server
```

### 步骤 3：创建 LiteLLM 配置文件

**文件路径**: `/opt/litellm-server/config/litellm-config.yaml`

```yaml
# LiteLLM 配置文件
# 模型列表配置
model_list:
  # OpenAI 模型
  - model_name: gpt-4
    litellm_params:
      model: openai/gpt-4-turbo
      api_key: ${OPENAI_API_KEY}
      api_base: https://api.openai.com/v1

  - model_name: gpt-3.5-turbo
    litellm_params:
      model: openai/gpt-3.5-turbo
      api_key: ${OPENAI_API_KEY}
      api_base: https://api.openai.com/v1

  # Claude 模型（如需要）
  - model_name: claude-3-sonnet
    litellm_params:
      model: anthropic/claude-3-sonnet-20240229
      api_key: ${ANTHROPIC_API_KEY}

  # 本地模型（如果有 Ollama/vLLM）
  - model_name: local-llama2
    litellm_params:
      model: openai/llama2
      api_base: http://localhost:8000/v1
      api_key: sk-local

# 全局设置
general_settings:
  # 主密钥（企业：只用于运维 bootstrap；不要下发给业务；不要存入 WordPress 数据库）
  master_key: ${LITELLM_MASTER_KEY}
  
  # 数据库连接
  database_url: postgresql://litellm_user:litellm_password@postgres:5432/litellm_db
  
  # Redis 缓存（可选但推荐）
  redis_url: redis://redis:6379
  
  # 生产默认关闭 debug（避免敏感信息泄露；排障时再临时打开）
  debug: false
  detailed_debug: false
  
  # 放弃不支持的参数
  drop_params: true

# 虚拟密钥配置
# 生产建议：由运维用 Master Key 生成“WordPress 专用 service key”，WordPress 再用该 key 管理业务 key
virtual_keys: []

# 日志配置
logging:
  type: file
  log_dir: /app/logs
  log_level: INFO

# 环境变量
environment_variables:
  OPENAI_API_KEY: ${OPENAI_API_KEY}
  ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
```

### 步骤 4：创建 Docker Compose 配置（建议直接用本仓库模板）

**文件路径（核心服务）**: `/opt/litellm-server/docker-compose.yml`  
**模板来源**: 本仓库 `docker-compose.core.yml`（复制为 `docker-compose.yml` 后再按需调整）

```yaml
version: '3.8'

services:
  # PostgreSQL 数据库
  postgres:
    image: postgres:16-alpine
    container_name: litellm-postgres
    environment:
      POSTGRES_USER: litellm_user
      POSTGRES_PASSWORD: litellm_password
      POSTGRES_DB: litellm_db
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./data/postgres_init.sql:/docker-entrypoint-initdb.d/init.sql
    # 生产不暴露数据库端口到宿主机（需要临时排障时再用 `docker compose exec` 进入容器）
    networks:
      - litellm-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U litellm_user"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Redis 缓存（可选）
  redis:
    image: redis:7-alpine
    container_name: litellm-redis
    volumes:
      - redis_data:/data
    # 生产不暴露 Redis 端口到宿主机
    networks:
      - litellm-network
    command: redis-server --appendonly yes

  # LiteLLM Proxy 服务
  litellm:
    # 生产必须锁定版本：替换为你在预生产验收通过的 tag
    image: ghcr.io/berriai/litellm:vX.Y.Z
    container_name: litellm-proxy
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      # 核心配置
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
      DATABASE_URL: postgresql://litellm_user:litellm_password@postgres:5432/litellm_db
      REDIS_URL: redis://redis:6379
      
      # API 密钥
      OPENAI_API_KEY: ${OPENAI_API_KEY}
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
      
      # 日志配置
      LOG_LEVEL: INFO
      
      # 说明：WordPress 通过 PHP 服务器端调用 LiteLLM 管理接口不需要 CORS
      # 只有当你让浏览器端跨域直连 LiteLLM（不推荐用于管理接口）时，才配置域名白名单
      LITELLM_CORS_ORIGINS: ""
      
      # 健康检查
      HEALTHCHECK_ENABLED: "true"
    
    volumes:
      - ./config/litellm-config.yaml:/app/config.yaml
      - ./logs:/app/logs
      - litellm_data:/app/data
    
    # 关键：仅绑定 127.0.0.1，避免公网直连 24157
    ports:
      - "127.0.0.1:24157:24157"
    
    networks:
      - litellm-network
    
    command: >
      --config /app/config.yaml
      --port 24157
    
    restart: unless-stopped
    
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:24157/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # 观测栈（Prometheus/Grafana/告警/日志）建议独立 compose 文件管理，避免与核心服务耦合
  # 见本文「第三部分：观测与告警」

# 持久化存储
volumes:
  postgres_data:
    driver: local
  redis_data:
    driver: local
  litellm_data:
    driver: local

# 自定义网络
networks:
  litellm-network:
    driver: bridge
```

### 步骤 5：创建环境配置文件

**文件路径**: `/opt/litellm-server/.env`

> 建议从本仓库 `env.example` 复制为 `.env`，然后修改并 `chmod 600 .env`。

```bash
# LiteLLM 主配置（生产：随机高强度，仅运维保管）
LITELLM_MASTER_KEY=sk-your-secure-master-key

# 数据库配置
POSTGRES_USER=litellm_user
POSTGRES_PASSWORD=litellm_password
POSTGRES_DB=litellm_db

# OpenAI API
OPENAI_API_KEY=sk-xxx-your-real-openai-key

# Anthropic API（如需要）
ANTHROPIC_API_KEY=sk-ant-xxx-your-real-anthropic-key

# 日志级别
LOG_LEVEL=INFO

# 环境
ENVIRONMENT=production
```

### 步骤 6：启动 LiteLLM 服务

```bash
# 进入项目目录
cd /opt/litellm-server

# 设置环境变量权限
chmod 600 .env

# 启动核心服务
docker compose up -d

# 查看服务状态
docker compose ps

# 查看日志
docker compose logs -f litellm

# 等待服务启动（通常需要30-60秒）
sleep 60

# 测试 LiteLLM 健康状态
curl http://localhost:24157/health
```

### 步骤 7：验证部署

```bash
# 1. 检查 LiteLLM Web UI
# 生产建议通过反向代理域名访问（不要直连 :24157）

# 2. 测试 API 连接
curl -X POST http://localhost:24157/v1/chat/completions \
  -H "Authorization: Bearer sk-<SERVICE_KEY_NOT_MASTER>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [{"role": "user", "content": "Hello"}],
    "temperature": 0.7
  }'

# 3. 获取数据库连接信息
docker compose exec postgres psql -U litellm_user -d litellm_db -c "\dt"
```

---

## 第二部分：WordPress 侧集成（企业级插件设计要点）

本仓库当前仅提供插件的“示例代码片段”（偏 POC）。企业落地时，WordPress 插件需要按以下强制原则实现，否则不建议上线：

- **密钥模型（最小权限）**：Master Key 只用于运维 bootstrap；WordPress 后台使用“专用 service key”管理业务 key；禁止把 Master Key 下发给业务或写进 WP 数据库
- **密钥存放**：禁止把 master/service key 明文存到 `wp_options`；推荐从 `wp-config.php` 常量或 systemd/PHP-FPM 环境变量注入读取
- **权限与审计**：为插件定义独立 capability；对创建/删除/禁用 key 记录审计日志（操作者/时间/IP/变更内容）
- **接口兼容**：统计接口（文档里示例的 `/api/analytics`）需要按你最终锁定的 LiteLLM 版本对齐；不要假设路径恒定
- **前端可靠性**：图表刷新必须复用/销毁 Chart 实例，避免后台长期打开导致内存泄漏

下面的步骤保留为“参考实现结构”，你可以在此基础上实现企业级版本。

### 步骤 1：创建 WordPress 插件结构

```bash
# 进入 WordPress 插件目录
cd /var/www/html/wp-content/plugins

# 创建插件目录
mkdir -p litellm-dashboard

# 创建必要文件
cd litellm-dashboard
touch litellm-dashboard.php
mkdir -p assets/css assets/js includes
touch includes/admin-page.php includes/api-handler.php
touch assets/css/admin-style.css assets/js/admin-script.js
```

### 步骤 2：创建主插件文件

**文件路径**: `/wp-content/plugins/litellm-dashboard/litellm-dashboard.php`

```php
<?php
/**
 * Plugin Name: LiteLLM Dashboard
 * Plugin URI: https://your-company.com
 * Description: WordPress 中的 LiteLLM 仪表盘集成，提供 API Key 管理、实时监控和数据可视化
 * Version: 1.0.0
 * Author: Your Company
 * Author URI: https://your-company.com
 * License: GPL v2 or later
 * Text Domain: litellm-dashboard
 * Domain Path: /languages
 * Requires at least: 5.9
 * Requires PHP: 7.4
 */

defined('ABSPATH') || exit;

// 定义常量
define('LITELLM_PLUGIN_DIR', plugin_dir_path(__FILE__));
define('LITELLM_PLUGIN_URL', plugin_dir_url(__FILE__));
define('LITELLM_PLUGIN_BASENAME', plugin_basename(__FILE__));

// 主插件类
class LiteLLM_Dashboard {
    
    private static $instance = null;
    
    /**
     * 获取单例实例
     */
    public static function get_instance() {
        if (null === self::$instance) {
            self::$instance = new self();
        }
        return self::$instance;
    }
    
    /**
     * 构造函数
     */
    public function __construct() {
        // 加载文本域
        add_action('plugins_loaded', [$this, 'load_textdomain']);
        
        // 注册钩子
        add_action('init', [$this, 'init']);
        add_action('admin_init', [$this, 'admin_init']);
        add_action('admin_menu', [$this, 'add_admin_menu']);
        add_action('admin_enqueue_scripts', [$this, 'enqueue_assets']);
        
        // AJAX 钩子
        add_action('wp_ajax_litellm_get_settings', [$this, 'ajax_get_settings']);
        add_action('wp_ajax_litellm_save_settings', [$this, 'ajax_save_settings']);
        add_action('wp_ajax_litellm_get_stats', [$this, 'ajax_get_stats']);
        add_action('wp_ajax_litellm_create_key', [$this, 'ajax_create_key']);
        add_action('wp_ajax_litellm_list_keys', [$this, 'ajax_list_keys']);
        add_action('wp_ajax_litellm_delete_key', [$this, 'ajax_delete_key']);
        add_action('wp_ajax_litellm_get_dashboard_data', [$this, 'ajax_get_dashboard_data']);
        
        // 激活和停用钩子
        register_activation_hook(__FILE__, [$this, 'activate']);
        register_deactivation_hook(__FILE__, [$this, 'deactivate']);
    }
    
    /**
     * 插件激活
     */
    public function activate() {
        // 创建默认选项
        if (!get_option('litellm_settings')) {
            add_option('litellm_settings', [
                'api_base' => 'http://localhost:24157',
                'master_key' => '',
                'enabled' => false
            ]);
        }
        
        // 刷新重写规则
        flush_rewrite_rules();
    }
    
    /**
     * 插件停用
     */
    public function deactivate() {
        flush_rewrite_rules();
    }
    
    /**
     * 加载文本域
     */
    public function load_textdomain() {
        load_plugin_textdomain(
            'litellm-dashboard',
            false,
            dirname(LITELLM_PLUGIN_BASENAME) . '/languages'
        );
    }
    
    /**
     * 初始化
     */
    public function init() {
        // 初始化代码
    }
    
    /**
     * 管理员初始化
     */
    public function admin_init() {
        // 注册设置
        register_setting('litellm_settings_group', 'litellm_settings');
    }
    
    /**
     * 添加管理菜单
     */
    public function add_admin_menu() {
        add_menu_page(
            'LiteLLM Dashboard',
            'LiteLLM',
            'manage_options',
            'litellm-dashboard',
            [$this, 'render_dashboard_page'],
            'dashicons-chart-bar',
            99
        );
        
        add_submenu_page(
            'litellm-dashboard',
            '仪表盘',
            '仪表盘',
            'manage_options',
            'litellm-dashboard'
        );
        
        add_submenu_page(
            'litellm-dashboard',
            'API Key 管理',
            'API Key 管理',
            'manage_options',
            'litellm-keys',
            [$this, 'render_keys_page']
        );
        
        add_submenu_page(
            'litellm-dashboard',
            '设置',
            '设置',
            'manage_options',
            'litellm-settings',
            [$this, 'render_settings_page']
        );
    }
    
    /**
     * 注册资源
     */
    public function enqueue_assets($hook) {
        // 检查是否在 LiteLLM 页面
        if (strpos($hook, 'litellm') === false) {
            return;
        }
        
        // 注册样式
        wp_register_style(
            'litellm-admin-css',
            LITELLM_PLUGIN_URL . 'assets/css/admin-style.css',
            [],
            '1.0.0'
        );
        
        // 注册脚本
        wp_register_script(
            'litellm-admin-js',
            LITELLM_PLUGIN_URL . 'assets/js/admin-script.js',
            ['jquery', 'jquery-ui-tabs', 'chart'],
            '1.0.0',
            true
        );
        
        // 加载 Chart.js 用于数据可视化
        wp_enqueue_script(
            'chart',
            'https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.js',
            [],
            '4.4.0',
            true
        );
        
        // 加载资源
        wp_enqueue_style('litellm-admin-css');
        wp_enqueue_script('litellm-admin-js');
        
        // 传递 PHP 数据到 JavaScript
        wp_localize_script('litellm-admin-js', 'litellmConfig', [
            'ajaxUrl' => admin_url('admin-ajax.php'),
            'nonce' => wp_create_nonce('litellm_nonce'),
            'apiBase' => get_option('litellm_settings')['api_base'] ?? 'http://localhost:24157'
        ]);
    }
    
    /**
     * 渲染仪表盘页面
     */
    public function render_dashboard_page() {
        if (!current_user_can('manage_options')) {
            wp_die('Permission denied');
        }
        
        // 获取设置
        $settings = get_option('litellm_settings', []);
        $is_configured = !empty($settings['master_key']) && $settings['api_base'];
        
        ?>
        <div class="wrap">
            <h1><?php esc_html_e('LiteLLM 仪表盘', 'litellm-dashboard'); ?></h1>
            
            <?php if (!$is_configured): ?>
                <div class="notice notice-warning">
                    <p><?php esc_html_e('请先配置 LiteLLM 连接信息。', 'litellm-dashboard'); ?>
                        <a href="<?php echo admin_url('admin.php?page=litellm-settings'); ?>">
                            <?php esc_html_e('去设置', 'litellm-dashboard'); ?>
                        </a>
                    </p>
                </div>
            <?php else: ?>
                <div id="litellm-dashboard-container">
                    <!-- 统计卡片 -->
                    <div class="litellm-stats">
                        <div class="stat-card">
                            <div class="stat-title"><?php esc_html_e('API 请求数', 'litellm-dashboard'); ?></div>
                            <div class="stat-value" id="stat-requests">-</div>
                        </div>
                        <div class="stat-card">
                            <div class="stat-title"><?php esc_html_e('总 Tokens', 'litellm-dashboard'); ?></div>
                            <div class="stat-value" id="stat-tokens">-</div>
                        </div>
                        <div class="stat-card">
                            <div class="stat-title"><?php esc_html_e('总成本', 'litellm-dashboard'); ?></div>
                            <div class="stat-value" id="stat-cost">-</div>
                        </div>
                        <div class="stat-card">
                            <div class="stat-title"><?php esc_html_e('错误率', 'litellm-dashboard'); ?></div>
                            <div class="stat-value" id="stat-error-rate">-</div>
                        </div>
                    </div>
                    
                    <!-- 图表区域 -->
                    <div class="litellm-charts">
                        <div class="chart-container">
                            <h2><?php esc_html_e('请求趋势', 'litellm-dashboard'); ?></h2>
                            <canvas id="requestChart"></canvas>
                        </div>
                        <div class="chart-container">
                            <h2><?php esc_html_e('成本分布', 'litellm-dashboard'); ?></h2>
                            <canvas id="costChart"></canvas>
                        </div>
                    </div>
                    
                    <!-- 内嵌 LiteLLM Web UI -->
                    <div class="litellm-webui-container">
                        <h2><?php esc_html_e('LiteLLM Web 控制面板', 'litellm-dashboard'); ?></h2>
                        <iframe 
                            id="litellm-iframe"
                            src="<?php echo esc_url($settings['api_base']); ?>/ui" 
                            width="100%" 
                            height="1200" 
                            frameborder="0"
                            style="border: 1px solid #ddd; border-radius: 5px; margin-top: 20px;">
                        </iframe>
                    </div>
                </div>
            <?php endif; ?>
        </div>
        <?php
    }
    
    /**
     * 渲染 API Key 管理页面
     */
    public function render_keys_page() {
        if (!current_user_can('manage_options')) {
            wp_die('Permission denied');
        }
        
        ?>
        <div class="wrap">
            <h1><?php esc_html_e('API Key 管理', 'litellm-dashboard'); ?></h1>
            
            <div class="litellm-keys-container">
                <!-- 创建新密钥 -->
                <div class="key-creation-form">
                    <h2><?php esc_html_e('创建新 API Key', 'litellm-dashboard'); ?></h2>
                    <form id="litellm-create-key-form">
                        <?php wp_nonce_field('litellm_nonce', 'litellm_nonce'); ?>
                        
                        <table class="form-table">
                            <tr>
                                <th><label for="key_name"><?php esc_html_e('密钥名称', 'litellm-dashboard'); ?></label></th>
                                <td>
                                    <input type="text" id="key_name" name="key_name" class="regular-text" required>
                                    <p class="description"><?php esc_html_e('为此密钥起一个描述性名称', 'litellm-dashboard'); ?></p>
                                </td>
                            </tr>
                            <tr>
                                <th><label for="key_models"><?php esc_html_e('允许的模型', 'litellm-dashboard'); ?></label></th>
                                <td>
                                    <input type="text" id="key_models" name="key_models" class="regular-text" placeholder="gpt-3.5-turbo,gpt-4">
                                    <p class="description"><?php esc_html_e('以逗号分隔的模型列表', 'litellm-dashboard'); ?></p>
                                </td>
                            </tr>
                            <tr>
                                <th><label for="key_budget"><?php esc_html_e('预算限制 ($)', 'litellm-dashboard'); ?></label></th>
                                <td>
                                    <input type="number" id="key_budget" name="key_budget" step="0.01" min="0" value="100">
                                    <p class="description"><?php esc_html_e('此密钥的最大成本限制', 'litellm-dashboard'); ?></p>
                                </td>
                            </tr>
                            <tr>
                                <th><label for="key_rpm"><?php esc_html_e('RPM 限制', 'litellm-dashboard'); ?></label></th>
                                <td>
                                    <input type="number" id="key_rpm" name="key_rpm" min="0" value="100">
                                    <p class="description"><?php esc_html_e('每分钟请求数限制', 'litellm-dashboard'); ?></p>
                                </td>
                            </tr>
                        </table>
                        
                        <p class="submit">
                            <button type="submit" class="button button-primary"><?php esc_html_e('创建密钥', 'litellm-dashboard'); ?></button>
                        </p>
                    </form>
                </div>
                
                <!-- 密钥列表 -->
                <div class="key-list">
                    <h2><?php esc_html_e('已存在的密钥', 'litellm-dashboard'); ?></h2>
                    <table class="wp-list-table widefat striped">
                        <thead>
                            <tr>
                                <th><?php esc_html_e('密钥名称', 'litellm-dashboard'); ?></th>
                                <th><?php esc_html_e('密钥', 'litellm-dashboard'); ?></th>
                                <th><?php esc_html_e('状态', 'litellm-dashboard'); ?></th>
                                <th><?php esc_html_e('预算', 'litellm-dashboard'); ?></th>
                                <th><?php esc_html_e('操作', 'litellm-dashboard'); ?></th>
                            </tr>
                        </thead>
                        <tbody id="litellm-keys-list">
                            <tr><td colspan="5"><?php esc_html_e('加载中...', 'litellm-dashboard'); ?></td></tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
        <?php
    }
    
    /**
     * 渲染设置页面
     */
    public function render_settings_page() {
        if (!current_user_can('manage_options')) {
            wp_die('Permission denied');
        }
        
        $settings = get_option('litellm_settings', []);
        
        ?>
        <div class="wrap">
            <h1><?php esc_html_e('LiteLLM 设置', 'litellm-dashboard'); ?></h1>
            
            <form id="litellm-settings-form" method="post">
                <?php wp_nonce_field('litellm_nonce', 'litellm_nonce'); ?>
                
                <table class="form-table">
                    <tr>
                        <th><label for="api_base"><?php esc_html_e('API 基础 URL', 'litellm-dashboard'); ?></label></th>
                        <td>
                            <input type="url" id="api_base" name="api_base" class="regular-text" value="<?php echo esc_attr($settings['api_base'] ?? ''); ?>" required>
                            <p class="description"><?php esc_html_e('例如：http://localhost:24157 或 https://litellm.yourcompany.com', 'litellm-dashboard'); ?></p>
                        </td>
                    </tr>
                    <tr>
                        <th><label for="master_key"><?php esc_html_e('主密钥 (Master Key)', 'litellm-dashboard'); ?></label></th>
                        <td>
                            <input type="password" id="master_key" name="master_key" class="regular-text" value="<?php echo esc_attr($settings['master_key'] ?? ''); ?>" required>
                            <p class="description"><?php esc_html_e('输入 LiteLLM Master Key 以启用完整功能', 'litellm-dashboard'); ?></p>
                        </td>
                    </tr>
                    <tr>
                        <th><label for="enabled"><?php esc_html_e('启用集成', 'litellm-dashboard'); ?></label></th>
                        <td>
                            <input type="checkbox" id="enabled" name="enabled" value="1" <?php checked($settings['enabled'] ?? false, true); ?>>
                            <label for="enabled"><?php esc_html_e('启用 LiteLLM 集成', 'litellm-dashboard'); ?></label>
                        </td>
                    </tr>
                </table>
                
                <p class="submit">
                    <button type="submit" class="button button-primary"><?php esc_html_e('保存设置', 'litellm-dashboard'); ?></button>
                </p>
            </form>
        </div>
        <?php
    }
    
    /**
     * AJAX：获取设置
     */
    public function ajax_get_settings() {
        check_ajax_referer('litellm_nonce', 'nonce');
        
        if (!current_user_can('manage_options')) {
            wp_send_json_error('Permission denied');
        }
        
        $settings = get_option('litellm_settings', []);
        wp_send_json_success($settings);
    }
    
    /**
     * AJAX：保存设置
     */
    public function ajax_save_settings() {
        check_ajax_referer('litellm_nonce', 'nonce');
        
        if (!current_user_can('manage_options')) {
            wp_send_json_error('Permission denied');
        }
        
        $settings = [
            'api_base' => sanitize_url($_POST['api_base'] ?? ''),
            'master_key' => sanitize_text_field($_POST['master_key'] ?? ''),
            'enabled' => isset($_POST['enabled'])
        ];
        
        update_option('litellm_settings', $settings);
        wp_send_json_success('Settings saved');
    }
    
    /**
     * AJAX：获取统计数据
     */
    public function ajax_get_stats() {
        check_ajax_referer('litellm_nonce', 'nonce');
        
        if (!current_user_can('manage_options')) {
            wp_send_json_error('Permission denied');
        }
        
        $settings = get_option('litellm_settings', []);
        
        if (empty($settings['api_base']) || empty($settings['master_key'])) {
            wp_send_json_error('LiteLLM not configured');
        }
        
        // 调用 LiteLLM API 获取统计数据
        $response = wp_remote_get(
            $settings['api_base'] . '/api/analytics',
            [
                'headers' => [
                    'Authorization' => 'Bearer ' . $settings['master_key']
                ],
                'timeout' => 10
            ]
        );
        
        if (is_wp_error($response)) {
            wp_send_json_error($response->get_error_message());
        }
        
        $data = json_decode(wp_remote_retrieve_body($response), true);
        wp_send_json_success($data);
    }
    
    /**
     * AJAX：创建 API Key
     */
    public function ajax_create_key() {
        check_ajax_referer('litellm_nonce', 'nonce');
        
        if (!current_user_can('manage_options')) {
            wp_send_json_error('Permission denied');
        }
        
        $settings = get_option('litellm_settings', []);
        
        $payload = [
            'key_name' => sanitize_text_field($_POST['key_name'] ?? ''),
            'models' => array_map('trim', explode(',', $_POST['key_models'] ?? '')),
            'max_budget' => floatval($_POST['key_budget'] ?? 0),
            'rpm_limit' => intval($_POST['key_rpm'] ?? 0)
        ];
        
        $response = wp_remote_post(
            $settings['api_base'] . '/key/generate',
            [
                'headers' => [
                    'Authorization' => 'Bearer ' . $settings['master_key'],
                    'Content-Type' => 'application/json'
                ],
                'body' => json_encode($payload),
                'timeout' => 10
            ]
        );
        
        if (is_wp_error($response)) {
            wp_send_json_error($response->get_error_message());
        }
        
        $data = json_decode(wp_remote_retrieve_body($response), true);
        wp_send_json_success($data);
    }
    
    /**
     * AJAX：列出密钥
     */
    public function ajax_list_keys() {
        check_ajax_referer('litellm_nonce', 'nonce');
        
        if (!current_user_can('manage_options')) {
            wp_send_json_error('Permission denied');
        }
        
        $settings = get_option('litellm_settings', []);
        
        $response = wp_remote_get(
            $settings['api_base'] . '/key/list',
            [
                'headers' => [
                    'Authorization' => 'Bearer ' . $settings['master_key']
                ],
                'timeout' => 10
            ]
        );
        
        if (is_wp_error($response)) {
            wp_send_json_error($response->get_error_message());
        }
        
        $data = json_decode(wp_remote_retrieve_body($response), true);
        wp_send_json_success($data);
    }
    
    /**
     * AJAX：删除密钥
     */
    public function ajax_delete_key() {
        check_ajax_referer('litellm_nonce', 'nonce');
        
        if (!current_user_can('manage_options')) {
            wp_send_json_error('Permission denied');
        }
        
        $settings = get_option('litellm_settings', []);
        $key = sanitize_text_field($_POST['key'] ?? '');
        
        $response = wp_remote_post(
            $settings['api_base'] . '/key/delete',
            [
                'headers' => [
                    'Authorization' => 'Bearer ' . $settings['master_key'],
                    'Content-Type' => 'application/json'
                ],
                'body' => json_encode(['key' => $key]),
                'timeout' => 10
            ]
        );
        
        if (is_wp_error($response)) {
            wp_send_json_error($response->get_error_message());
        }
        
        wp_send_json_success('Key deleted');
    }
    
    /**
     * AJAX：获取仪表盘数据
     */
    public function ajax_get_dashboard_data() {
        check_ajax_referer('litellm_nonce', 'nonce');
        
        if (!current_user_can('manage_options')) {
            wp_send_json_error('Permission denied');
        }
        
        // 获取统计数据、请求历史等
        // 这些数据用于前端图表
        wp_send_json_success([
            'requests' => [1, 2, 3, 5, 8, 13, 21],
            'costs' => [10, 20, 15, 25, 30, 28, 32],
            'models' => ['gpt-3.5-turbo', 'gpt-4', 'claude-3']
        ]);
    }
}

// 初始化插件
LiteLLM_Dashboard::get_instance();
```

### 步骤 3：创建 CSS 样式

**文件路径**: `/wp-content/plugins/litellm-dashboard/assets/css/admin-style.css`

```css
/* LiteLLM Dashboard 样式 */

.litellm-stats {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 20px;
    margin-bottom: 30px;
}

.stat-card {
    background: white;
    border: 1px solid #e5e5e5;
    border-radius: 5px;
    padding: 20px;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
}

.stat-card .stat-title {
    font-size: 14px;
    color: #666;
    margin-bottom: 10px;
    font-weight: 500;
}

.stat-card .stat-value {
    font-size: 32px;
    font-weight: bold;
    color: #0073aa;
}

.litellm-charts {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
    gap: 20px;
    margin-bottom: 30px;
}

.chart-container {
    background: white;
    border: 1px solid #e5e5e5;
    border-radius: 5px;
    padding: 20px;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
}

.chart-container h2 {
    margin-top: 0;
    margin-bottom: 15px;
    font-size: 16px;
    color: #333;
}

.litellm-webui-container {
    background: white;
    border: 1px solid #e5e5e5;
    border-radius: 5px;
    padding: 20px;
    margin-top: 30px;
}

.litellm-webui-container h2 {
    margin-top: 0;
    margin-bottom: 15px;
    font-size: 16px;
    color: #333;
}

.litellm-webui-container iframe {
    max-width: 100%;
}

/* Key 管理样式 */
.litellm-keys-container {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 20px;
}

.key-creation-form,
.key-list {
    background: white;
    border: 1px solid #e5e5e5;
    border-radius: 5px;
    padding: 20px;
}

.key-creation-form h2,
.key-list h2 {
    margin-top: 0;
    margin-bottom: 15px;
}

.key-list table {
    width: 100%;
}

.key-list table th,
.key-list table td {
    padding: 10px;
    text-align: left;
    border-bottom: 1px solid #e5e5e5;
}

.key-list table th {
    background: #f5f5f5;
    font-weight: 600;
}

/* 表单样式 */
.form-table th {
    width: 200px;
}

.regular-text {
    width: 100%;
    padding: 8px;
    border: 1px solid #ddd;
    border-radius: 4px;
}

.submit {
    margin-top: 20px;
}

.button {
    padding: 8px 16px;
    border: none;
    border-radius: 4px;
    cursor: pointer;
    font-size: 14px;
}

.button-primary {
    background: #0073aa;
    color: white;
}

.button-primary:hover {
    background: #005a87;
}

/* 响应式设计 */
@media (max-width: 768px) {
    .litellm-stats {
        grid-template-columns: 1fr;
    }
    
    .litellm-charts {
        grid-template-columns: 1fr;
    }
    
    .litellm-keys-container {
        grid-template-columns: 1fr;
    }
}
```

### 步骤 4：创建 JavaScript

**文件路径**: `/wp-content/plugins/litellm-dashboard/assets/js/admin-script.js`

```javascript
// LiteLLM Dashboard JavaScript

jQuery(document).ready(function($) {
    'use strict';
    
    // 初始化
    init();
    
    function init() {
        if ($('#litellm-dashboard-container').length) {
            loadDashboardData();
            setInterval(loadDashboardData, 30000); // 每30秒刷新一次
        }
        
        if ($('#litellm-create-key-form').length) {
            handleKeyCreation();
            loadKeys();
        }
        
        if ($('#litellm-settings-form').length) {
            handleSettingsSave();
        }
    }
    
    // 加载仪表盘数据
    function loadDashboardData() {
        $.ajax({
            url: litellmConfig.ajaxUrl,
            type: 'POST',
            data: {
                action: 'litellm_get_stats',
                nonce: litellmConfig.nonce
            },
            success: function(response) {
                if (response.success) {
                    updateStats(response.data);
                    updateCharts(response.data);
                }
            },
            error: function(error) {
                console.error('Failed to load dashboard data:', error);
            }
        });
    }
    
    // 更新统计数据
    function updateStats(data) {
        $('#stat-requests').text(data.total_requests || 0);
        $('#stat-tokens').text(data.total_tokens || 0);
        $('#stat-cost').text('$' + (data.total_cost || 0).toFixed(2));
        $('#stat-error-rate').text((data.error_rate || 0).toFixed(2) + '%');
    }
    
    // 更新图表
    function updateCharts(data) {
        // 请求趋势图
        var requestCtx = document.getElementById('requestChart');
        if (requestCtx) {
            new Chart(requestCtx, {
                type: 'line',
                data: {
                    labels: ['Day 1', 'Day 2', 'Day 3', 'Day 4', 'Day 5', 'Day 6', 'Day 7'],
                    datasets: [{
                        label: 'API 请求数',
                        data: data.daily_requests || [0, 0, 0, 0, 0, 0, 0],
                        borderColor: '#0073aa',
                        backgroundColor: 'rgba(0, 115, 170, 0.1)',
                        tension: 0.4
                    }]
                },
                options: {
                    responsive: true,
                    plugins: {
                        legend: {
                            display: true,
                            position: 'top',
                        }
                    }
                }
            });
        }
        
        // 成本分布图
        var costCtx = document.getElementById('costChart');
        if (costCtx) {
            new Chart(costCtx, {
                type: 'doughnut',
                data: {
                    labels: data.models || ['Model 1', 'Model 2', 'Model 3'],
                    datasets: [{
                        data: data.model_costs || [30, 40, 30],
                        backgroundColor: [
                            '#0073aa',
                            '#61afd9',
                            '#92c5e9'
                        ]
                    }]
                },
                options: {
                    responsive: true,
                    plugins: {
                        legend: {
                            display: true,
                            position: 'bottom',
                        }
                    }
                }
            });
        }
    }
    
    // 处理 API Key 创建
    function handleKeyCreation() {
        $('#litellm-create-key-form').on('submit', function(e) {
            e.preventDefault();
            
            $.ajax({
                url: litellmConfig.ajaxUrl,
                type: 'POST',
                data: {
                    action: 'litellm_create_key',
                    nonce: litellmConfig.nonce,
                    key_name: $('#key_name').val(),
                    key_models: $('#key_models').val(),
                    key_budget: $('#key_budget').val(),
                    key_rpm: $('#key_rpm').val()
                },
                success: function(response) {
                    if (response.success) {
                        alert('API Key created successfully!');
                        $('#litellm-create-key-form')[0].reset();
                        loadKeys();
                    } else {
                        alert('Error: ' + response.data);
                    }
                },
                error: function(error) {
                    alert('Failed to create key');
                    console.error(error);
                }
            });
        });
    }
    
    // 加载密钥列表
    function loadKeys() {
        $.ajax({
            url: litellmConfig.ajaxUrl,
            type: 'POST',
            data: {
                action: 'litellm_list_keys',
                nonce: litellmConfig.nonce
            },
            success: function(response) {
                if (response.success) {
                    displayKeys(response.data);
                }
            },
            error: function(error) {
                console.error('Failed to load keys:', error);
            }
        });
    }
    
    // 显示密钥列表
    function displayKeys(keys) {
        var html = '';
        if (keys && keys.length > 0) {
            keys.forEach(function(key) {
                html += '<tr>';
                html += '<td>' + (key.key_name || 'N/A') + '</td>';
                html += '<td><code>' + (key.key || 'N/A').substring(0, 20) + '...</code></td>';
                html += '<td>' + (key.status || 'active') + '</td>';
                html += '<td>$' + (key.max_budget || 0).toFixed(2) + '</td>';
                html += '<td>';
                html += '<button class="button delete-key" data-key="' + (key.key || '') + '">Delete</button>';
                html += '</td>';
                html += '</tr>';
            });
        } else {
            html = '<tr><td colspan="5">No keys found</td></tr>';
        }
        
        $('#litellm-keys-list').html(html);
        
        // 绑定删除事件
        $('.delete-key').on('click', function() {
            if (confirm('Are you sure you want to delete this key?')) {
                deleteKey($(this).data('key'));
            }
        });
    }
    
    // 删除密钥
    function deleteKey(key) {
        $.ajax({
            url: litellmConfig.ajaxUrl,
            type: 'POST',
            data: {
                action: 'litellm_delete_key',
                nonce: litellmConfig.nonce,
                key: key
            },
            success: function(response) {
                if (response.success) {
                    alert('Key deleted successfully');
                    loadKeys();
                } else {
                    alert('Error: ' + response.data);
                }
            },
            error: function(error) {
                alert('Failed to delete key');
                console.error(error);
            }
        });
    }
    
    // 处理设置保存
    function handleSettingsSave() {
        $('#litellm-settings-form').on('submit', function(e) {
            e.preventDefault();
            
            $.ajax({
                url: litellmConfig.ajaxUrl,
                type: 'POST',
                data: {
                    action: 'litellm_save_settings',
                    nonce: litellmConfig.nonce,
                    api_base: $('#api_base').val(),
                    master_key: $('#master_key').val(),
                    enabled: $('#enabled').is(':checked') ? 1 : 0
                },
                success: function(response) {
                    if (response.success) {
                        alert('Settings saved successfully!');
                    } else {
                        alert('Error: ' + response.data);
                    }
                },
                error: function(error) {
                    alert('Failed to save settings');
                    console.error(error);
                }
            });
        });
    }
});
```

---

## 第三部分：观测与告警（Prometheus/Grafana/日志）

企业落地要求：除了 LiteLLM 原生 `/ui`，还需要覆盖 **宿主机、容器、数据库、反向代理、WordPress/PHP-FPM** 的全链路观测。

### 3.1 推荐组件（同机部署）
- **Prometheus**：指标采集与告警规则评估
- **Grafana**：统一仪表盘（LiteLLM + 主机 + 容器 + PostgreSQL + Nginx）
- **node_exporter**：宿主机 CPU/内存/磁盘/网络
- **cAdvisor**：容器资源与重启/OOM
- **Alertmanager**：告警分发（邮件/企业微信/钉钉/Slack 等）
- **（可选）Loki + Promtail**：日志聚合与检索（替代 “上服务器 grep”）

### 3.2 关键指标（建议至少）
- **可用性**：`/health` 探活；5xx 占比；上游提供方错误率
- **性能**：延迟 p95/p99；队列/重试；PostgreSQL 连接耗尽风险
- **容量**：CPU/内存/磁盘水位；容器 OOM；日志盘增长
- **业务**：按模型/按 key 的请求量、token、成本（以你锁定版本支持为准）

> 本仓库会提供可直接落地的配置模板（见 `observability/` 目录：Prometheus 抓取配置、告警规则示例等）。

### 3.3 启动方式（推荐）

在 `/opt/litellm-server` 目录下（已存在 `docker-compose.yml` 核心服务）：

```bash
# 启动/更新观测栈（与核心服务共用 litellm-network）
docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d

# 访问（均建议仅本机回环或经 VPN/堡垒机）
curl -fsS http://127.0.0.1:9090/-/healthy     # Prometheus
curl -fsS http://127.0.0.1:3000/api/health    # Grafana
curl -fsS http://127.0.0.1:9093/-/healthy     # Alertmanager
```

---

## 第四部分：安全基线（强制项）

### 4.1 网络暴露面（强制）
- `:24157` 必须只绑定 `127.0.0.1`（或完全不映射宿主机端口，只通过反代访问）
- PostgreSQL/Redis 不映射宿主机端口
- 防火墙仅放行必要端口（通常 `22/80/443`）

### 4.2 iframe 嵌入与安全头（强制）
如果你要在 WordPress 后台 iframe 嵌入 LiteLLM `/ui`：
- 不要依赖 `X-Frame-Options: ALLOW-FROM`（现代浏览器兼容性差）
- 推荐由 **反向代理层**统一设置 CSP：`Content-Security-Policy: frame-ancestors https://<your-wordpress-domain>`
- 必要时在反代层 **移除/覆盖** 上游返回的 `X-Frame-Options`（否则会被 `SAMEORIGIN` 挡住）

### 4.3 CORS（按需，默认收敛）
WordPress 插件走 PHP 服务器端调用 LiteLLM 管理接口时 **不需要 CORS**。只有当你让浏览器端跨域直连 LiteLLM（不推荐用于管理接口）时，才配置严格域名白名单。

### 步骤 1：配置 Nginx 反向代理

**文件路径（宿主机 Nginx，建议与 WordPress 共用）**: `/etc/nginx/sites-available/litellm.conf`（示例）

```nginx
server {
    listen 80;
    server_name litellm.yourcompany.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name litellm.yourcompany.com;

    # SSL（建议直接引用 Let's Encrypt 证书路径）
    ssl_certificate /etc/letsencrypt/live/litellm.yourcompany.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/litellm.yourcompany.com/privkey.pem;

    # 通用安全头（按你们安全规范增补）
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;

    # 允许 WordPress 后台 iframe 嵌入 LiteLLM UI（用 CSP，而不是 ALLOW-FROM）
    proxy_hide_header X-Frame-Options;
    add_header Content-Security-Policy "frame-ancestors https://your-wordpress-domain.com" always;

    # 反代到本机回环（对应 docker 端口映射 127.0.0.1:24157:24157）
    location / {
        proxy_pass http://127.0.0.1:24157;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 60s;
    }

    location /v1/ {
        proxy_pass http://127.0.0.1:24157/v1/;
        proxy_set_header Host $host;
        proxy_set_header Authorization $http_authorization;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /ui/ {
        proxy_pass http://127.0.0.1:24157/ui/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 步骤 3：SSL 证书配置

```bash
# 使用 Let's Encrypt 获取免费 SSL 证书
sudo apt install -y certbot python3-certbot-nginx

# 获取证书并自动写入 Nginx 配置（推荐）
sudo certbot --nginx -d litellm.yourcompany.com

# 设置自动续期
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer
```

### 步骤 4：设置防火墙

```bash
# 使用 UFW（Ubuntu 默认防火墙）
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
# 明确拒绝 LiteLLM 直连端口（即使你已经仅绑定 127.0.0.1，也建议显式拒绝）
sudo ufw deny 24157/tcp
sudo ufw enable

# 或使用 iptables
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -j DROP
```

---

## 第五部分：完整集成步骤

### 总体集成流程

```
Step 1: 部署 LiteLLM 服务
   ↓
Step 2: 验证 LiteLLM 正常运行
   ↓
Step 3: 创建 WordPress 插件
   ↓
Step 4: 激活插件并配置
   ↓
Step 5: 测试端到端集成
   ↓
Step 6: 监控和优化
```

### 集成清单

#### 1. LiteLLM 服务验证

```bash
# 检查所有容器是否运行
docker compose ps

# 验证 LiteLLM 健康状态
curl http://localhost:24157/health

# 用 Master Key 生成 WordPress 专用 service key（只给 WP 后端使用）
curl -X POST http://localhost:24157/key/generate \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "key_name": "wordpress_admin_service",
    "models": ["gpt-3.5-turbo", "gpt-4"],
    "max_budget": 1000,
    "rpm_limit": 100
  }'

# 获取生成的 key：保存到安全位置（推荐写入 wp-config.php 常量或 systemd 环境变量），不要存入 wp_options
```

#### 2. WordPress 插件安装

```bash
# 将插件文件上传到 WordPress
scp -r /path/to/litellm-dashboard/ user@wordpress-server:/var/www/html/wp-content/plugins/

# 或使用 WordPress CLI
wp plugin install /path/to/litellm-dashboard.zip --activate
```

#### 3. WordPress 配置

1. 登录 WordPress 管理后台
2. 导航到 **插件** → 启用 **LiteLLM Dashboard**
3. 导航到 **LiteLLM** → **设置**
4. 填入：
   - **API 基础 URL**: `https://litellm.yourcompany.com` 或 `http://localhost:24157`
   - **主密钥**: 从 LiteLLM 获取的密钥
5. 勾选 **启用集成**
6. 点击 **保存设置**

#### 4. 功能测试

```bash
# 测试 API 连接
curl -X POST https://your-wordpress.com/wp-admin/admin-ajax.php \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "action=litellm_get_stats&nonce=YOUR_NONCE"

# 查看 WordPress 日志
tail -f /var/www/html/wp-content/debug.log
```

---

## 第六部分：故障排查

### 常见问题

| 问题 | 症状 | 解决方案 |
|------|------|--------|
| **iframe 加载失败** | 跨域错误 | 检查 CORS 配置和 X-Frame-Options |
| **API Key 无效** | 401 Unauthorized | 验证 Master Key 和 API Base URL |
| **数据库连接失败** | 500 错误 | 检查 PostgreSQL 连接字符串 |
| **性能缓慢** | 加载时间长 | 启用 Redis 缓存，优化数据库查询 |
| **内存不足** | OOM Killer | 增加 Docker 内存限制 |

### 调试命令

```bash
# 查看 LiteLLM 日志
docker compose logs -f litellm

# 检查 PostgreSQL 连接
docker compose exec postgres psql -U litellm_user -d litellm_db -c "SELECT COUNT(*) FROM api_keys;"

# 查看 API 密钥列表
curl -H "Authorization: Bearer YOUR_MASTER_KEY" \
  http://localhost:24157/key/list

# 性能测试
ab -n 100 -c 10 http://localhost:24157/health

# 网络诊断
docker compose exec litellm ping postgres
docker compose exec litellm curl http://localhost:24157/health
```

### 日志收集

```bash
# 收集所有日志
docker compose logs > /tmp/litellm-logs.txt

# 查看特定服务日志
docker compose logs postgres
docker compose logs litellm
docker compose logs nginx

# 实时监控
watch 'docker compose ps'
```

---

## 检查清单

- [ ] 服务器已准备好（4核CPU、8GB内存、50GB磁盘）
- [ ] Docker 和 Docker Compose 已安装
- [ ] 创建了项目目录结构
- [ ] 配置了 litellm-config.yaml
- [ ] 配置了 docker-compose.yml
- [ ] 配置了 .env 文件
- [ ] LiteLLM 服务已成功启动
- [ ] Web UI 可访问（http://localhost:24157/ui）
- [ ] 创建了 WordPress 插件
- [ ] 插件已上传到 WordPress
- [ ] 插件已在 WordPress 激活
- [ ] 在 WordPress 中配置了 API 连接
- [ ] 测试了端到端集成
- [ ] 配置了 SSL/TLS
- [ ] 配置了防火墙规则
- [ ] 设置了监控和日志

---

## 性能优化建议

### 1. 数据库优化
```sql
-- 创建索引加快查询
CREATE INDEX idx_api_keys_user_id ON api_keys(user_id);
CREATE INDEX idx_api_logs_created_at ON api_logs(created_at);
```

### 2. 缓存配置
```yaml
# 在 litellm-config.yaml 中启用 Redis
general_settings:
  redis_url: redis://redis:6379
  cache_ttl: 3600
```

### 3. Docker 资源限制
```yaml
services:
  litellm:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G
        reservations:
          cpus: '1'
          memory: 2G
```

---

## 支持和维护

- **文档**: https://docs.litellm.ai
- **GitHub**: https://github.com/BerriAI/litellm
- **问题报告**: GitHub Issues
- **定期备份**: 每周备份 PostgreSQL 数据库

