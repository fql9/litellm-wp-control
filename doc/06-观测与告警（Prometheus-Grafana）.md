# 观测与告警（Prometheus / Grafana / Alertmanager）

> [< 上一篇：WordPress 集成](05-WordPress-集成（企业级要点）.md) | [返回目录](README.md) | [下一篇：安全基线 >](07-安全基线（强制项）.md)

> 文档默认 LiteLLM 版本：**v1.80.11**（更新日期：**2026-01-13**）

## 目标

除 LiteLLM 原生 `/ui` 外，补齐企业必需的全链路观测：
- 服务可用性（探活/5xx/上游失败）
- 性能（p95/p99、排队/重试）
- 容量（CPU/内存/磁盘、容器 OOM/重启）
- 数据库健康（连接数、慢查询风险）

## 本项目提供的模板

- `../docker-compose.observability.yml`
- `../observability/prometheus/prometheus.yml`
- `../observability/prometheus/rules.yml`
- `../observability/alertmanager/alertmanager.yml`
- `../observability/grafana/provisioning/`
- `../observability/blackbox/blackbox.yml`

## 启动方式（与核心服务共用网络）

> 说明：本仓库部署脚本 `scripts/deploy-full.sh` 默认会启动观测栈；你也可以用下面命令手动启动/更新。

```bash
cd /opt/litellm-server
docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d
```

## 访问方式（默认仅本机回环）

- Prometheus：`http://127.0.0.1:9090`
- Grafana：`http://127.0.0.1:3000`
- Alertmanager：`http://127.0.0.1:9093`

> 生产建议：这些组件也只开放给内网/VPN/堡垒机，不要直接公网暴露。

## Grafana 初始账号与改密（强制）

Grafana 默认账号/密码在 `docker-compose.observability.yml` 里通过环境变量设置（示例里通常为弱口令占位）。

生产建议（至少做到其一）：

- 修改 Grafana 管理员密码为强口令
- 接入企业 SSO（LDAP/OIDC/SAML，视你们体系）
- 限制访问来源（仅 VPN/堡垒机）

## 告警接入（强烈建议）

`observability/alertmanager/alertmanager.yml` 目前是示例 receiver，你需要替换为你们真实的告警通道（企业微信/钉钉/飞书/Webhook/邮件）。

## 常用自检命令

```bash
# Prometheus 健康
curl -fsS http://127.0.0.1:9090/-/healthy

# Grafana 健康
curl -fsS http://127.0.0.1:3000/api/health

# Alertmanager 健康
curl -fsS http://127.0.0.1:9093/-/healthy
```
