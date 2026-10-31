# Nền tảng `k3d`

Cluster lab: cluster GitOps mà `deploy/k8s/gitops.sh` của repo code dựng (vai stg trên máy, trên runner của `verify.yml`). Cluster k3d chạy
đúng values gốc của `base/`, nên thư mục này không có values nào; root `argocd/apps` với `platform=k3d` ra đúng các Application như trước khi
có lớp nền tảng. Component chỉ của k3d: `cloudnative-pg`, `plugin-barman-cloud` (trường `platforms` của `components.json`).
