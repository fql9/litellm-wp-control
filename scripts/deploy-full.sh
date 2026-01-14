#!/usr/bin/env bash
set -euo pipefail

# 企业级 LiteLLM 部署脚本（LiteLLM：Docker Compose）
# 安全默认：
# - LiteLLM 仅绑定 127.0.0.1:${LITELLM_PORT}
# - 强制要求你显式锁定 LiteLLM 镜像版本（LITELLM_IMAGE）
# - 生成随机 Master Key / PostgreSQL 密码（如未提供）
# - 不会默认开启 UFW（避免误封 SSH），需显式 --enable-ufw

LITELLM_PORT="${LITELLM_PORT:-24157}"
LITELLM_DIR="${LITELLM_DIR:-/opt/litellm-server}"

LITELLM_IMAGE_ARG=""
INSTALL_DEPS=0
ENABLE_UFW=0
SSH_PORT=22
PRINT_SERVICE_KEY=0
YES=0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<EOF
用法：
  sudo ./scripts/deploy-full.sh \\
    --litellm-image ghcr.io/berriai/litellm:v1.80.11 \\
    --install-deps \\
    --enable-ufw --ssh-port 22 \\
    --yes

单独获取/生成 service key：
  sudo ./scripts/deploy-full.sh --service-key

可选：
  --litellm-image       指定 LiteLLM 镜像（强烈推荐用此参数自动写入 .env，避免手工编辑）
  --install-deps       安装依赖（docker/compose/jq/ufw）
  --enable-ufw         配置 UFW（默认不启用，避免误封 SSH）
  --ssh-port N         SSH 端口（默认 22）
  --litellm-dir PATH   部署目录（默认 /opt/litellm-server）
  --service-key        输出（必要时生成）service key，并写入 <litellm-dir>/service-key.txt
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
    die "请使用 sudo 运行（需要写 /opt，且可能配置 ufw）。"
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
      --litellm-image) LITELLM_IMAGE_ARG="${2:-}"; shift 2 ;;
      --install-deps) INSTALL_DEPS=1; shift ;;
      --enable-ufw) ENABLE_UFW=1; shift ;;
      --ssh-port) SSH_PORT="${2:-22}"; shift 2 ;;
      --litellm-dir) LITELLM_DIR="${2:-}"; shift 2 ;;
      --service-key) PRINT_SERVICE_KEY=1; shift ;;
      --yes) YES=1; shift ;;
      *) die "未知参数：$1（用 --help 查看用法）" ;;
    esac
  done
}

install_deps() {
  echo "==> 安装依赖（docker/compose/jq/ufw）"
  apt-get update -y
  apt-get install -y \
    ca-certificates curl gnupg lsb-release \
    docker.io docker-compose-plugin \
    python3 \
    ufw \
    jq
  systemctl enable --now docker
}

prepare_litellm_dir() {
  echo "==> 准备部署目录：${LITELLM_DIR}"
  mkdir -p "${LITELLM_DIR}/config" "${LITELLM_DIR}/logs" "${LITELLM_DIR}/data"
  chmod 755 "${LITELLM_DIR}"

  # 复制模板
  cp -f "${REPO_ROOT}/docker-compose.core.yml" "${LITELLM_DIR}/docker-compose.yml"
  cp -f "${REPO_ROOT}/config/litellm-config.yaml" "${LITELLM_DIR}/config/litellm-config.yaml"
  chmod -R 755 "${LITELLM_DIR}/config"

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
    # replace placeholder / change_me / sk-your-... only if still default-like
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

  # 强制要求锁定版本（禁止占位符/滚动 tag）
  local img
  img="$(grep -E "^LITELLM_IMAGE=" "${env_file}" | tail -n 1 | cut -d= -f2- || true)"
  if [[ -z "${img}" || "${img}" == "ghcr.io/berriai/litellm:vX.Y.Z" ]]; then
    if [[ "${YES}" -eq 1 ]]; then
      echo "!! 你需要在 ${env_file} 中设置 LITELLM_IMAGE=ghcr.io/berriai/litellm:v1.80.11（或你验收通过的稳定版本）"
      echo "   文档默认版本：v1.80.11（更新日期：2026-01-13）"
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

#
# 注意：按你的要求，本脚本不处理 Nginx/HTTPS，也不参与 WordPress 集成。
# 如需对外反代，请使用仓库 `nginx/litellm.conf` 自行配置（建议仅内网/VPN 暴露）。
#

start_services() {
  echo "==> 启动 LiteLLM 核心服务"
  (cd "${LITELLM_DIR}" && docker compose up -d)
  curl -fsS "http://127.0.0.1:${LITELLM_PORT}/health" >/dev/null
  echo "    LiteLLM health OK: http://127.0.0.1:${LITELLM_PORT}/health"
}

get_or_create_service_key() {
  local env_file="${LITELLM_DIR}/.env"
  local service_key_file="${LITELLM_DIR}/service-key.txt"
  local master
  master="$(grep -E "^LITELLM_MASTER_KEY=" "${env_file}" | tail -n 1 | cut -d= -f2-)"

  if [[ -f "${service_key_file}" ]]; then
    local existing
    existing="$(cat "${service_key_file}" 2>/dev/null || true)"
    if [[ -n "${existing}" ]]; then
      echo "==> 读取已存在的 service key：${service_key_file}" >&2
      echo "${existing}"
      return 0
    fi
  fi

  echo "==> 生成 service key（用于管理/发放业务 key）" >&2
  local resp
  resp="$(curl -fsS -X POST "http://127.0.0.1:${LITELLM_PORT}/key/generate" \
    -H "Authorization: Bearer ${master}" \
    -H "Content-Type: application/json" \
    -d '{"key_name":"litellm_admin_service","models":["gpt-3.5-turbo","gpt-4"],"max_budget":1000,"rpm_limit":100}')"

  local key
  key="$(echo "${resp}" | python3 - <<'PY'
import json,sys
data=json.load(sys.stdin)
print(data.get("key",""))
PY
)"

  [[ -n "${key}" ]] || die "生成 service key 失败（响应：${resp})"
  umask 077
  mkdir -p "$(dirname "${service_key_file}")"
  echo "${key}" > "${service_key_file}"
  chmod 600 "${service_key_file}" || true
  echo "    已写入：${service_key_file}" >&2

  echo "${key}"
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

  # 仅输出/生成 service key（不改系统配置）
  if [[ "${PRINT_SERVICE_KEY}" -eq 1 ]]; then
    # 确保已部署目录与 env
    [[ -f "${LITELLM_DIR}/.env" ]] || die "未找到 ${LITELLM_DIR}/.env，请先部署 LiteLLM 或指定 --litellm-dir"
    # 确保服务可用（必要时启动）
    if ! curl -fsS "http://127.0.0.1:${LITELLM_PORT}/health" >/dev/null 2>&1; then
      echo "==> LiteLLM 未运行，尝试启动（docker compose up -d）"
      (cd "${LITELLM_DIR}" && docker compose up -d)
    fi
    curl -fsS "http://127.0.0.1:${LITELLM_PORT}/health" >/dev/null || die "LiteLLM 未就绪，无法生成 service key"
    echo ""
    key="$(get_or_create_service_key)"
    echo ""
    echo "service key：${key}"
    echo "保存位置：${LITELLM_DIR}/service-key.txt"
    exit 0
  fi

  if [[ "${INSTALL_DEPS}" -eq 1 ]]; then
    install_deps
  fi

  prepare_litellm_dir
  ensure_env_values

  start_services

  if [[ "${ENABLE_UFW}" -eq 1 ]]; then
    configure_ufw
  fi

  echo ""
  echo "==> 完成"
  echo "- LiteLLM 仅本机回环：       http://127.0.0.1:${LITELLM_PORT}"
  echo ""
  echo "后续："
  echo "- 获取/生成 service key：sudo bash scripts/deploy-full.sh --service-key"
  echo "- 如需对外访问（HTTP）请自行配置反代（参考 nginx/litellm.conf），并建议只在内网/VPN 暴露。"
}

main "$@"

