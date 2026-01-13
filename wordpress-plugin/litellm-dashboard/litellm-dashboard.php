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
     * 优先从 wp-config.php 常量读取（企业推荐，避免密钥落库）
     */
    private function get_api_base(): string {
        if (defined('LITELLM_API_BASE') && is_string(LITELLM_API_BASE) && LITELLM_API_BASE !== '') {
            return rtrim(LITELLM_API_BASE, '/');
        }
        $settings = get_option('litellm_settings', []);
        return rtrim($settings['api_base'] ?? 'http://localhost:24157', '/');
    }

    /**
     * WordPress 侧用于调用 LiteLLM 管理接口的 key（推荐：service key）
     * - 优先读取 LITELLM_SERVICE_KEY 常量
     * - 兼容旧字段（示例插件里仍叫 master_key）
     */
    private function get_admin_key(): string {
        if (defined('LITELLM_SERVICE_KEY') && is_string(LITELLM_SERVICE_KEY) && LITELLM_SERVICE_KEY !== '') {
            return LITELLM_SERVICE_KEY;
        }
        $settings = get_option('litellm_settings', []);
        return (string) ($settings['master_key'] ?? '');
    }

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
            'apiBase' => $this->get_api_base()
        ]);
    }

    /**
     * 渲染仪表盘页面
     */
    public function render_dashboard_page() {
        if (!current_user_can('manage_options')) {
            wp_die('Permission denied');
        }

        // 获取设置（企业推荐：从常量读取）
        $api_base = $this->get_api_base();
        $is_configured = !empty($this->get_admin_key()) && !empty($api_base);

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
                            src="<?php echo esc_url($api_base); ?>/ui"
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
        $api_base = $this->get_api_base();
        $using_const_api_base = defined('LITELLM_API_BASE') && is_string(LITELLM_API_BASE) && LITELLM_API_BASE !== '';
        $using_const_key = defined('LITELLM_SERVICE_KEY') && is_string(LITELLM_SERVICE_KEY) && LITELLM_SERVICE_KEY !== '';

        ?>
        <div class="wrap">
            <h1><?php esc_html_e('LiteLLM 设置', 'litellm-dashboard'); ?></h1>

            <form id="litellm-settings-form" method="post">
                <?php wp_nonce_field('litellm_nonce', 'litellm_nonce'); ?>

                <table class="form-table">
                    <tr>
                        <th><label for="api_base"><?php esc_html_e('API 基础 URL', 'litellm-dashboard'); ?></label></th>
                        <td>
                            <input type="url" id="api_base" name="api_base" class="regular-text" value="<?php echo esc_attr($api_base ?? ''); ?>" <?php echo $using_const_api_base ? 'readonly' : ''; ?> required>
                            <p class="description"><?php esc_html_e('例如：http://localhost:24157 或 http://litellm.yourcompany.com', 'litellm-dashboard'); ?></p>
                            <?php if ($using_const_api_base): ?>
                                <p class="description"><strong><?php esc_html_e('当前由 wp-config.php 常量 LITELLM_API_BASE 注入（推荐）。', 'litellm-dashboard'); ?></strong></p>
                            <?php endif; ?>
                        </td>
                    </tr>
                    <tr>
                        <th><label for="master_key"><?php esc_html_e('Service Key（推荐）', 'litellm-dashboard'); ?></label></th>
                        <td>
                            <input type="password" id="master_key" name="master_key" class="regular-text" value="" <?php echo $using_const_key ? 'readonly' : ''; ?> <?php echo $using_const_key ? '' : 'required'; ?>>
                            <p class="description"><?php esc_html_e('生产建议：使用 WordPress 专用 service key，并通过 wp-config.php 常量 LITELLM_SERVICE_KEY 注入（不要把 Master Key/Service Key 明文存入数据库）。', 'litellm-dashboard'); ?></p>
                            <?php if ($using_const_key): ?>
                                <p class="description"><strong><?php esc_html_e('当前由 wp-config.php 常量 LITELLM_SERVICE_KEY 注入（推荐）。', 'litellm-dashboard'); ?></strong></p>
                            <?php endif; ?>
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
        // 不返回密钥（避免泄露）
        $settings['master_key'] = '';
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

        $settings = get_option('litellm_settings', []);
        $settings['api_base'] = sanitize_url($_POST['api_base'] ?? '');
        $settings['enabled'] = isset($_POST['enabled']);

        // 如果未通过常量注入，则允许保存（示例/POC 用；生产不推荐）
        if (!(defined('LITELLM_SERVICE_KEY') && is_string(LITELLM_SERVICE_KEY) && LITELLM_SERVICE_KEY !== '')) {
            $settings['master_key'] = sanitize_text_field($_POST['master_key'] ?? '');
        }

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

        $api_base = $this->get_api_base();
        $admin_key = $this->get_admin_key();

        if (empty($api_base) || empty($admin_key)) {
            wp_send_json_error('LiteLLM not configured');
        }

        // 调用 LiteLLM API 获取统计数据
        $response = wp_remote_get(
            $api_base . '/api/analytics',
            [
                'headers' => [
                    'Authorization' => 'Bearer ' . $admin_key
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

        $api_base = $this->get_api_base();
        $admin_key = $this->get_admin_key();
        if (empty($api_base) || empty($admin_key)) {
            wp_send_json_error('LiteLLM not configured');
        }

        $payload = [
            'key_name' => sanitize_text_field($_POST['key_name'] ?? ''),
            'models' => array_map('trim', explode(',', $_POST['key_models'] ?? '')),
            'max_budget' => floatval($_POST['key_budget'] ?? 0),
            'rpm_limit' => intval($_POST['key_rpm'] ?? 0)
        ];

        $response = wp_remote_post(
            $api_base . '/key/generate',
            [
                'headers' => [
                    'Authorization' => 'Bearer ' . $admin_key,
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

        $api_base = $this->get_api_base();
        $admin_key = $this->get_admin_key();
        if (empty($api_base) || empty($admin_key)) {
            wp_send_json_error('LiteLLM not configured');
        }

        $response = wp_remote_get(
            $api_base . '/key/list',
            [
                'headers' => [
                    'Authorization' => 'Bearer ' . $admin_key
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

        $api_base = $this->get_api_base();
        $admin_key = $this->get_admin_key();
        if (empty($api_base) || empty($admin_key)) {
            wp_send_json_error('LiteLLM not configured');
        }
        $key = sanitize_text_field($_POST['key'] ?? '');

        $response = wp_remote_post(
            $api_base . '/key/delete',
            [
                'headers' => [
                    'Authorization' => 'Bearer ' . $admin_key,
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

