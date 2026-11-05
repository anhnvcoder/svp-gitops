# Nền tảng `k3d`

Cluster lab: cluster GitOps mà `deploy/k8s/gitops.sh` của repo code dựng (vai stg trên máy, trên runner của `verify.yml`). Cluster k3d chạy
values gốc của `base/`; khác biệt duy nhất ở đây là nguồn Secret: `svp-cluster.yaml` bật External Secrets với store `kubernetes`, đọc Secret
nguồn ở namespace `svp-secrets` mà `deploy/k8s/secrets.sh` của repo code ghi từ `.env` (trên `eks` là AWS Secrets Manager). Component chỉ của
k3d: `cloudnative-pg`, `plugin-barman-cloud` (trường `platforms` của `components.json`).
