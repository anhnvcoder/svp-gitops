# Nền tảng `k3d`

Cluster lab: cluster GitOps mà `deploy/k8s/gitops.sh` của repo code dựng (vai stg trên máy, trên runner của `verify.yml`). Cluster k3d chạy
values gốc của `base/`; khác biệt duy nhất ở đây là nguồn Secret: `svp-cluster.yaml` bật External Secrets với store `kubernetes`, đọc Secret
nguồn ở namespace `svp-secrets` mà `deploy/k8s/secrets.sh` của repo code ghi từ `.env` (trên `eks` là AWS Secrets Manager). Component chỉ của
k3d: `cloudnative-pg`, `plugin-barman-cloud`, `loki`, `tempo` (trường `platforms` của `components.json`).

Telemetry ở lại trong cluster như compose: Collector gửi metric, log, trace tới Prometheus, Loki, Tempo (`collector.destinations` mặc định
của chart `svp-observability`), luật chạy ở Prometheus, cảnh báo qua Alertmanager, dashboard ở Grafana của `kube-prometheus-stack`. Trên
`eks`, cùng luật và dashboard đi tới dịch vụ managed của account (`platforms/eks/`).

Kafka (Apache Kafka KRaft) và Valkey chạy trong `svp-data` theo `base/`, chỉ nhận TLS với cert ký bởi CA local (Secret `local-ca`, chỉ
render ở k3d): service tin nó qua `localCA` mặc định của chart `svp-service`, Collector qua volume và biến của `base/otel-collector.yaml`,
KEDA qua tham số `ca` của ClusterTriggerAuthentication `keda-kafka` (chart `svp-data`). `platforms/eks/` gỡ cả ba: MSK và ElastiCache
dùng cert của CA công khai.
