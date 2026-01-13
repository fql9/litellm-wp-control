# 观测与告警（Prometheus / Grafana / Alertmanager）

> [< 上一篇：WordPress 集成](05-WordPress-集成（企业级要点）.md) | [返回目录](README.md) | [下一篇：安全基线 >](07-安全基线（强制项）.md)

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

```bash
cd /opt/litellm-server
docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d
```

## 访问方式（默认仅本机回环）

- Prometheus：`http://127.0.0.1:9090`
- Grafana：`http://127.0.0.1:3000`
- Alertmanager：`http://127.0.0.1:9093`

> 生产建议：这些组件也只开放给内网/VPN/堡垒机，不要直接公网暴露。

