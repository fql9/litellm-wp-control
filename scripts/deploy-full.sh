#!/usr/bin/env bash
set -euo pipefail

# 企业级“全功能完整部署”脚本（同机：WordPress 原生 + LiteLLM Docker + Nginx HTTPS + 观测栈 + 插件）
# 安全默认：
# - LiteLLM 仅绑定 127.0.0.1:${LITELLM_PORT}
# - 强制要求你显式锁定 LiteLLM 镜像版本（LITELLM_IMAGE）
# - 生成随机 Master Key / PostgreSQL 密码（如未提供）
# - 不会默认开启 UFW（避免误封 SSH），需显式 --enable-ufw

LITELLM_PORT="${LITELLM_PORT:-24157}"
LITELLM_DIR="${LITELLM_DIR:-/opt/litellm-server}"
WP_ROOT="${WP_ROOT:-/var/www/html}"
WP_CONFIG="${WP_CONFIG:-${WP_ROOT}/wp-config.php}"

LITELLM_DOMAIN=""
WP_DOMAIN=""
EMAIL=""
LITELLM_IMAGE_ARG=""
INSTALL_DEPS=0
ENABLE_TLS=0
ENABLE_UFW=0
SSH_PORT=22
START_OBSERVABILITY=1
DEPLOY_WP_PLUGIN=1
CONFIGURE_WP_CONFIG=0
YES=0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<EOF
用法：
  sudo ./scripts/deploy-full.sh \\
    --litellm-domain litellm.example.com \\
    --wp-domain wp.example.com \\
    --email admin@example.com \\
    --litellm-image ghcr.io/berriai/litellm:vX.Y.Z \\
    --install-deps \\
    --enable-tls \\
    --enable-ufw --ssh-port 22 \\
    --configure-wp-config \\
    --yes

必填：
  --litellm-domain     LiteLLM 对外域名（用于 Nginx/证书）
  --wp-domain          WordPress 域名（用于 CSP frame-ancestors）

可选：
  --email              certbot 邮箱（推荐）
  --litellm-image       指定 LiteLLM 镜像（强烈推荐用此参数自动写入 .env，避免手工编辑）
  --install-deps       安装依赖（docker/nginx/certbot/ufw）
  --enable-tls         使用 certbot 申请/配置 HTTPS（需要 DNS 已指向本机）
  --enable-ufw         配置 UFW（默认不启用，避免误封 SSH）
  --ssh-port N         SSH 端口（默认 22）
  --no-observability   不启动观测栈（不推荐）
  --no-wp-plugin       不部署 WordPress 插件
  --wp-root PATH       WordPress 根目录（默认 /var/www/html）
  --wp-config PATH     wp-config.php 路径（默认 \${WP_ROOT}/wp-config.php）
  --litellm-dir PATH   部署目录（默认 /opt/litellm-server）
  --configure-wp-config 自动写入 wp-config.php 常量（推荐，避免 key 落库）
  --yes                非交互确认

重要说明：
- 你必须在 .env 中设置 LITELLM_IMAGE（锁定版本），否则脚本会退出。
  参考官方仓库：https://github.com/BerriAI/litellm
EOF
}

die() { echo "错误: $*" >&2; exit 1; }

confirm() {
  if [[ "${YES}" -eq 1 ]]; then
    return 0
  fi
  read -r -p "$1 [y/N] " ans
  [[ "${ans}" == "y" || "${ans}" == "Y" ]]
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "请使用 sudo 运行（需要写 /opt、/etc/nginx、可选配置 ufw）。"
  fi
}

rand_secret() {
  # 32 bytes hex
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --litellm-domain) LITELLM_DOMAIN="${2:-}"; shift 2 ;;
      --wp-domain) WP_DOMAIN="${2:-}"; shift 2 ;;
      --email) EMAIL="${2:-}"; shift 2 ;;
      --litellm-image) LITELLM_IMAGE_ARG="${2:-}"; shift 2 ;;
      --install-deps) INSTALL_DEPS=1; shift ;;
      --enable-tls) ENABLE_TLS=1; shift ;;
      --enable-ufw) ENABLE_UFW=1; shift ;;
      --ssh-port) SSH_PORT="${2:-22}"; shift 2 ;;
      --no-observability) START_OBSERVABILITY=0; shift ;;
      --no-wp-plugin) DEPLOY_WP_PLUGIN=0; shift ;;
      --wp-root) WP_ROOT="${2:-}"; WP_CONFIG="${WP_ROOT}/wp-config.php"; shift 2 ;;
      --wp-config) WP_CONFIG="${2:-}"; shift 2 ;;
      --litellm-dir) LITELLM_DIR="${2:-}"; shift 2 ;;
      --configure-wp-config) CONFIGURE_WP_CONFIG=1; shift ;;
      --yes) YES=1; shift ;;
      *) die "未知参数：$1（用 --help 查看用法）" ;;
    esac
  done

  [[ -n "${LITELLM_DOMAIN}" ]] || die "缺少 --litellm-domain"
  [[ -n "${WP_DOMAIN}" ]] || die "缺少 --wp-domain"
}

install_deps() {
  echo "==> 安装依赖（docker/nginx/certbot/ufw）"
  apt-get update -y
  apt-get install -y \
    ca-certificates curl gnupg lsb-release \
    docker.io docker-compose-plugin \
    nginx \
    certbot python3-certbot-nginx \
    ufw \
    jq
  systemctl enable --now docker
  systemctl enable --now nginx
}

prepare_litellm_dir() {
  echo "==> 准备部署目录：${LITELLM_DIR}"
  mkdir -p "${LITELLM_DIR}/config" "${LITELLM_DIR}/logs" "${LITELLM_DIR}/data" "${LITELLM_DIR}/observability"
  chmod 755 "${LITELLM_DIR}"

  # 复制模板
  cp -f "${REPO_ROOT}/docker-compose.core.yml" "${LITELLM_DIR}/docker-compose.yml"
  cp -f "${REPO_ROOT}/docker-compose.observability.yml" "${LITELLM_DIR}/docker-compose.observability.yml"
  cp -f "${REPO_ROOT}/config/litellm-config.yaml" "${LITELLM_DIR}/config/litellm-config.yaml"
  rm -rf "${LITELLM_DIR}/observability"
  cp -a "${REPO_ROOT}/observability" "${LITELLM_DIR}/observability"
  chmod -R 755 "${LITELLM_DIR}/config" "${LITELLM_DIR}/observability"

  # 生成 .env（若不存在）
  if [[ ! -f "${LITELLM_DIR}/.env" ]]; then
    cp -f "${REPO_ROOT}/env.example" "${LITELLM_DIR}/.env"
    chmod 600 "${LITELLM_DIR}/.env"
  fi
}

ensure_env_values() {
  echo "==> 校验/补齐 .env"
  local env_file="${LITELLM_DIR}/.env"

  # helper: set KEY=VALUE if missing or placeholder
  set_kv() {
    local key="$1"
    local value="$2"
    if ! grep -qE "^${key}=" "${env_file}"; then
      echo "${key}=${value}" >> "${env_file}"
      return
    fi
    # replace placeholder vX.Y.Z / change_me / sk-your-... only if still default-like
    local cur
    cur="$(grep -E "^${key}=" "${env_file}" | tail -n 1 | cut -d= -f2- || true)"
    if [[ "${cur}" == "vX.Y.Z" || "${cur}" == "sk-your-secure-master-key" || "${cur}" == "litellm_password_change_me" || "${cur}" == "sk-your-openai-key" || "${cur}" == "sk-your-anthropic-key" || "${cur}" == "ghcr.io/berriai/litellm:vX.Y.Z" ]]; then
      sed -i "s|^${key}=.*|${key}=${value}|g" "${env_file}"
    fi
  }

  set_kv "LITELLM_MASTER_KEY" "sk-$(rand_secret)"
  set_kv "POSTGRES_PASSWORD" "pg-$(rand_secret)"

  # 优先使用命令行参数写入镜像版本
  if [[ -n "${LITELLM_IMAGE_ARG}" ]]; then
    set_kv "LITELLM_IMAGE" "${LITELLM_IMAGE_ARG}"
  fi

  # 强制要求锁定版本（且不能是占位符 vX.Y.Z）
  local img
  img="$(grep -E "^LITELLM_IMAGE=" "${env_file}" | tail -n 1 | cut -d= -f2- || true)"
  if [[ -z "${img}" || "${img}" == "ghcr.io/berriai/litellm:vX.Y.Z" ]]; then
    if [[ "${YES}" -eq 1 ]]; then
      echo "!! 你需要在 ${env_file} 中设置 LITELLM_IMAGE=ghcr.io/berriai/litellm:vX.Y.Z（替换为真实版本）"
      echo "   参考官方仓库 Releases: https://github.com/BerriAI/litellm"
      die "缺少/未正确设置 LITELLM_IMAGE"
    fi
    echo "请输入 LiteLLM 镜像版本（建议从官方 Releases 选择稳定版）："
    echo "  参考：https://github.com/BerriAI/litellm"
    read -r -p "LITELLM_IMAGE= " img_in
    [[ -n "${img_in}" ]] || die "LITELLM_IMAGE 不能为空"
    set_kv "LITELLM_IMAGE" "${img_in}"
  fi

  # 上游密钥（可选，但建议至少配置一个提供方）
  # 注意：不建议通过命令行参数传递（会进入 shell history），这里用交互式输入（不回显）。
  if [[ "${YES}" -ne 1 ]]; then
    local openai
    openai="$(grep -E "^OPENAI_API_KEY=" "${env_file}" | tail -n 1 | cut -d= -f2- || true)"
    if [[ "${openai}" == "sk-your-openai-key" || -z "${openai}" ]]; then
      read -r -s -p "请输入 OPENAI_API_KEY（可留空跳过）： " openai_in
      echo ""
      if [[ -n "${openai_in}" ]]; then
        set_kv "OPENAI_API_KEY" "${openai_in}"
      fi
    fi

    local anthropic
    anthropic="$(grep -E "^ANTHROPIC_API_KEY=" "${env_file}" | tail -n 1 | cut -d= -f2- || true)"
    if [[ "${anthropic}" == "sk-your-anthropic-key" || -z "${anthropic}" ]]; then
      read -r -s -p "请输入 ANTHROPIC_API_KEY（可留空跳过）： " anthropic_in
      echo ""
      if [[ -n "${anthropic_in}" ]]; then
        set_kv "ANTHROPIC_API_KEY" "${anthropic_in}"
      fi
    fi
  fi
}

configure_nginx() {
  echo "==> 配置宿主机 Nginx 反代（${LITELLM_DOMAIN} -> 127.0.0.1:${LITELLM_PORT}）"
  local out="/etc/nginx/sites-available/litellm.conf"
  cp -f "${REPO_ROOT}/nginx/litellm.conf" "${out}"
  sed -i "s/litellm\\.yourcompany\\.com/${LITELLM_DOMAIN}/g" "${out}"
  sed -i "s/your-wordpress-domain\\.com/${WP_DOMAIN}/g" "${out}"
  # 将模板中的默认端口替换为实际端口（模板当前是 24157）
  sed -i -E "s/127\\.0\\.0\\.1:[0-9]+/127.0.0.1:${LITELLM_PORT}/g" "${out}"

  ln -sf "${out}" /etc/nginx/sites-enabled/litellm.conf
  nginx -t
  systemctl reload nginx
}

enable_tls() {
  echo "==> 申请/配置 HTTPS（certbot --nginx）"
  if [[ -n "${EMAIL}" ]]; then
    certbot --nginx --redirect -d "${LITELLM_DOMAIN}" -m "${EMAIL}" --agree-tos --non-interactive
  else
    certbot --nginx --redirect -d "${LITELLM_DOMAIN}"
  fi
}

start_services() {
  echo "==> 启动 LiteLLM 核心服务"
  (cd "${LITELLM_DIR}" && docker compose up -d)
  curl -fsS "http://127.0.0.1:${LITELLM_PORT}/health" >/dev/null
  echo "    LiteLLM health OK: http://127.0.0.1:${LITELLM_PORT}/health"

  if [[ "${START_OBSERVABILITY}" -eq 1 ]]; then
    echo "==> 启动观测栈（Prometheus/Grafana/Alertmanager/node_exporter/cAdvisor/blackbox）"
    (cd "${LITELLM_DIR}" && docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d)
  fi
}

deploy_wp_plugin() {
  echo "==> 部署 WordPress 插件（示例）到 ${WP_ROOT}/wp-content/plugins"
  local plugin_dst="${WP_ROOT}/wp-content/plugins/litellm-dashboard"
  [[ -d "${WP_ROOT}/wp-content/plugins" ]] || die "未找到 WordPress 插件目录：${WP_ROOT}/wp-content/plugins"
  rm -rf "${plugin_dst}"
  cp -a "${REPO_ROOT}/wordpress-plugin/litellm-dashboard" "${plugin_dst}"
  chown -R www-data:www-data "${plugin_dst}" || true
  find "${plugin_dst}" -type d -exec chmod 755 {} \;
  find "${plugin_dst}" -type f -exec chmod 644 {} \;
  echo "    请在 WordPress 后台启用插件：LiteLLM Dashboard"
}

generate_wp_service_key() {
  local env_file="${LITELLM_DIR}/.env"
  local master
  master="$(grep -E "^LITELLM_MASTER_KEY=" "${env_file}" | tail -n 1 | cut -d= -f2-)"

  echo "==> 生成 WordPress 专用 service key（仅给 WP 后端使用）"
  local resp
  resp="$(curl -fsS -X POST "http://127.0.0.1:${LITELLM_PORT}/key/generate" \
    -H "Authorization: Bearer ${master}" \
    -H "Content-Type: application/json" \
    -d '{"key_name":"wordpress_admin_service","models":["gpt-3.5-turbo","gpt-4"],"max_budget":1000,"rpm_limit":100}')"

  local key
  key="$(echo "${resp}" | python3 - <<'PY'
import json,sys
data=json.load(sys.stdin)
print(data.get("key",""))
PY
)"

  [[ -n "${key}" ]] || die "生成 service key 失败（响应：${resp})"
  echo "    WordPress service key：${key}"
  echo "    （请妥善保存；生产建议写入 wp-config.php 常量或系统环境变量，不要落库）"

  echo "${key}"
}

configure_wp_config() {
  [[ -f "${WP_CONFIG}" ]] || die "未找到 wp-config.php：${WP_CONFIG}"
  local service_key="$1"

  echo "==> 写入 wp-config.php 常量（避免 key 落库）"
  cp -f "${WP_CONFIG}" "${WP_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"

  # 幂等：先移除旧定义（如果存在）
  sed -i "/define('LITELLM_API_BASE'/d" "${WP_CONFIG}"
  sed -i "/define('LITELLM_SERVICE_KEY'/d" "${WP_CONFIG}"

  # 插入到 “stop editing” 之前
  local snippet
  local scheme="http"
  if [[ "${ENABLE_TLS}" -eq 1 ]]; then
    scheme="https"
  fi
  snippet=$'\n'\"define('LITELLM_API_BASE', '${scheme}://${LITELLM_DOMAIN}');\"$'\n'\"define('LITELLM_SERVICE_KEY', '${service_key}');\"$'\n'

  if grep -q "That's all, stop editing" "${WP_CONFIG}"; then
    sed -i "/That's all, stop editing/i ${snippet}" "${WP_CONFIG}"
  else
    echo "${snippet}" >> "${WP_CONFIG}"
  fi

  echo "    已写入：LITELLM_API_BASE / LITELLM_SERVICE_KEY"
}

configure_ufw() {
  echo "==> 配置 UFW（请确认 SSH 端口正确，否则可能断联）"
  if ! confirm "即将执行：ufw allow ${SSH_PORT}/tcp, 80/tcp, 443/tcp；ufw deny ${LITELLM_PORT}/tcp；并启用 ufw。继续吗？"; then
    echo "    已跳过 UFW 配置"
    return
  fi
  ufw allow "${SSH_PORT}/tcp"
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw deny "${LITELLM_PORT}/tcp"
  ufw --force enable
}

main() {
  need_root
  parse_args "$@"

  if [[ "${INSTALL_DEPS}" -eq 1 ]]; then
    install_deps
  fi

  prepare_litellm_dir
  ensure_env_values

  configure_nginx
  if [[ "${ENABLE_TLS}" -eq 1 ]]; then
    enable_tls
  fi

  start_services

  local service_key=""
  service_key="$(generate_wp_service_key)"

  if [[ "${DEPLOY_WP_PLUGIN}" -eq 1 ]]; then
    deploy_wp_plugin
  fi

  if [[ "${CONFIGURE_WP_CONFIG}" -eq 1 ]]; then
    configure_wp_config "${service_key}"
  fi

  if [[ "${ENABLE_UFW}" -eq 1 ]]; then
    configure_ufw
  fi

  echo ""
  echo "==> 完成"
  local scheme="http"
  if [[ "${ENABLE_TLS}" -eq 1 ]]; then
    scheme="https"
  fi
  echo "- LiteLLM 对外入口（反代）：${scheme}://${LITELLM_DOMAIN}"
  echo "- LiteLLM 原生 UI：          ${scheme}://${LITELLM_DOMAIN}/ui/"
  echo "- LiteLLM 仅本机回环：       http://127.0.0.1:${LITELLM_PORT}"
  if [[ "${START_OBSERVABILITY}" -eq 1 ]]; then
    echo "- Prometheus：               http://127.0.0.1:9090"
    echo "- Grafana：                  http://127.0.0.1:3000"
    echo "- Alertmanager：             http://127.0.0.1:9093"
  fi
  echo ""
  echo "后续："
  echo "- 在 WordPress 后台启用插件 LiteLLM Dashboard"
  echo "- 插件 API Base 建议使用 https://${LITELLM_DOMAIN}"
  echo "- 生产请勿把 key 落库；推荐使用 wp-config.php 常量（本脚本可用 --configure-wp-config）。"
}

main "$@"

