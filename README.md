# svp-gitops

Cấu hình triển khai của nền tảng video ngắn: values Helm, bản phát hành của từng môi trường và manifest Argo CD, do Argo CD của mỗi cluster đọc.

## Mục lục

- [Bối cảnh](#bối-cảnh)
- [Cài đặt](#cài-đặt)
- [Sử dụng](#sử-dụng)
- [Cấu trúc](#cấu-trúc)
- [Root hai tầng và bootstrap](#root-hai-tầng-và-bootstrap)
- [Lớp nền tảng](#lớp-nền-tảng)
- [Thành phần](docs/components.md)
- [Ai duyệt gì](#ai-duyệt-gì)
- [Promote](#promote)
- [Check](#check)
- [Tiêu đề PR](#tiêu-đề-pr)
- [Nguồn gốc](#nguồn-gốc)
- [Đóng góp](#đóng-góp)
- [Giấy phép](#giấy-phép)

## Bối cảnh

Repo code của nền tảng là [svp-backend](https://github.com/anhnvcoder/svp-backend); repo này giữ values
Helm gốc, khác biệt và bản phát hành của từng môi trường, manifest của Argo CD. Argo CD của mỗi cluster chỉ đọc repo này (và chart
của repo code ở đúng commit repo này ghim); cái gì chạy ở stg, prd chỉ đổi được qua pull request vào đây. Code, test, Dockerfile, chart
(`deploy/helm/*`) và CI build, quét, ký image ở repo code; riêng web client build, quét, ký ở repo của nó,
[svp-frontend](https://github.com/anhnvcoder/svp-frontend). Mỗi `envs/<env>/images/web.yaml` ghi bản nào đang chạy.

Repo public: **không có secret, token, khoá hay id App nào ở đây**. Values chỉ nêu tên Secret; giá trị nằm ở cluster (lab: `.env` của
máy chạy, qua External Secrets Operator) hay ở AWS Secrets Manager (mọi env trên EKS).

## Cài đặt

Repo là cấu hình, không có gì để cài hay build. Clone về:

```sh
git clone https://github.com/anhnvcoder/svp-gitops.git
```

Chạy check trên máy cần thêm Docker (`make docs-check`, zizmor) và bản clone đủ lịch sử của repo code
[svp-backend](https://github.com/anhnvcoder/svp-backend) cùng công cụ của nó (`gitops-check.sh`, mục [Check](#check)).

## Sử dụng

Mọi thay đổi vào cluster đi qua pull request vào repo này, qua check tổng `gitops-ok` (mục [Check](#check)). Kiểm tài liệu trên máy:

```sh
make docs-check
```

`make help` liệt kê các target.

## Cấu trúc

```text
base/                       values gốc của mọi môi trường; đường dev (make k8s-up của repo code) chỉ đọc lớp này
  <component>.yaml          values của chart upstream (cả argo-rollouts-amd64.yaml theo kiến trúc node)
  argo-cd.yaml              values của chính Argo CD
  services/<svc>.yaml       values của 7 release chart svp-service, không có khối image
platforms/<platform>/       k3d và eks: khác biệt của nền tảng (mục Lớp nền tảng)
  README.md                 nền tảng là gì
  <component>.yaml          values giống nhau trên mọi cluster của nền tảng
  <component>.values.tpl    mẫu sinh values từ giá trị cluster của root (thứ phụ thuộc account, buổi)
  argo-cd.yaml              values của Argo CD trên nền tảng, bootstrap đọc sau base/argo-cd.yaml (không là Application)
envs/<env>/                 stg và prd
  <component>.yaml          overlay: chỉ phần khác gốc, comment đầu file nói vì sao
  svp-policy.yaml           bật kiểm build provenance của Kyverno (requireProvenance: true)
  charts.yaml               commit của repo code mà chart của env chạy, cùng hai giá trị dẫn xuất từ commit đó;
                            prd thêm gitopsRevision, commit của repo này mà prd chạy (mục Root hai tầng và bootstrap)
  images/<svc>.yaml         7 file, mỗi file chỉ khối image (repository, tag, digest) của bản phát hành
argocd/
  project.yaml              AppProject svp và default (đã khoá)
  bootstrap.json            chart Argo CD: repo, chart, version, values (base/argo-cd.yaml)
  root/                     tầng 1 của root: đọc envs/<env>/, ra đúng một Application svp-apps
  apps/                     tầng 2, chart app-of-apps; components.json là danh sách component
.github/workflows/check.yml check của mỗi pull request và push main, check tổng gitops-ok
.github/workflows/pr-title.yml  tiêu đề PR theo Conventional Commits (mục Tiêu đề PR)
.github/workflows/scorecard.yml OpenSSF Scorecard của repo (mục Check)
CODEOWNERS, renovate.json
docs/components.md          cấu hình đáng chú ý của từng thành phần và lý do
Makefile                    docs-check (markdownlint-cli2 và lychee); cấu hình ở .markdownlint.yaml, lychee.toml
LICENSE                     Apache-2.0
```

Cấu hình đáng chú ý của từng thành phần (Argo CD, root, AppProject, chart upstream) và lý do: [`docs/components.md`](docs/components.md).

Thứ tự ghép values của một Application: `values.yaml` của chart → `base/` → `platforms/<platform>/<name>.yaml` → `envs/<env>/<name>.yaml`
→ `envs/<env>/images/<name>.yaml` → phần mẫu `platforms/<platform>/<name>.values.tpl` sinh ra. `base/`, `platforms/` là file values, đọc qua
nguồn `ref: values` ở revision của chart `argocd/apps`; overlay, file image (nội dung tầng 1 đọc ở revision root theo dõi) và phần mẫu sinh ra
gộp theo đúng thứ tự đó vào `helm.valuesObject`, Argo CD đọc sau mọi file values. Root từ chối lúc render (Argo CD báo `ComparisonError` trên root): tầng 1 khi env không có thư mục, thiếu `charts.yaml` hay có khoá
khác ba khoá của nó (cộng `gitopsRevision` 40 hex), file không phải map YAML, overlay của release `svp-service` có `image`, `canary`,
`httpRoute.name`, file `images/` có khoá ngoài `image`; tầng 2 khi overlay không trùng tên component, thiếu một trong 7 file `images/`, giá trị
của `charts.yaml` sai dạng, `platform` không đặt hay khác `k3d`, `eks`, trường `platforms` của
`components.json` sai, file của nền tảng không trùng component chạy trên nền tảng đó, không phải map YAML hay đặt `cluster`, file hay mẫu của
release `svp-service` có `image`, `canary`, `httpRoute.name`, `cluster` thiếu khoá hay sai dạng (mục dưới). `charts` là tên dành riêng,
không component nào được mang.

## Root hai tầng và bootstrap

Root `svp-root` là chart `argocd/root` (tầng 1) ở revision nó theo dõi (`refs/heads/main` trên EKS). Nó đọc `envs/<env>/`, kiểm phần chỉ nội
dung file cho thấy, rồi ra đúng một Application `svp-apps` (không finalizer): chart `argocd/apps` (tầng 2) ở revision R, values gồm nội dung
từng overlay, từng file `images/`, ba giá trị của `charts.yaml` (`envFiles`), `env`, `platform`, `nodeArch`, `cluster`. R là `gitopsRevision`
của `envs/<env>/charts.yaml` khi env ghim, không thì chính revision của root. Tầng 2 ra một Application mỗi component: chart, `base/`,
`platforms/` đọc ở R qua một nguồn duy nhất của repo này (`ref: values`); overlay và image của `envs/<env>/` đi trong `valuesObject`, nên nội dung
là bản ở revision của root. Không dùng nguồn thứ hai của repo này ở revision khác cho `envs/<env>/`: repo-server của Argo CD từ chối Application
có file values trỏ một repo ở hai revision. Vì sao hai tầng (generator của ApplicationSet chỉ đưa nội dung một file thành tham số):
[ADR-0048](https://github.com/anhnvcoder/svp-backend/blob/main/docs/adr/0048-prd-aws.md) §7 của repo code.

- **Ghim prd:** khoá `gitopsRevision` (commit đủ 40 hex của repo này) chỉ ở `envs/prd/charts.yaml`, chỉ promote prd ghi (mục
  [Promote](#promote)): commit stg đã chạy. Có khoá thì mọi thứ trừ `envs/prd/` (chart `argocd/apps`, `components.json`, `base/`, `platforms/`)
  là bản ở commit đó, nên một thay đổi của `base/` hay `platforms/` trên `main` tới prd chỉ qua lần promote sau; `envs/prd/` (overlay, image,
  chart, khoá) vẫn đọc ở `main`, một PR promote đổi cả bộ cùng lúc. Khoá vắng thì như stg: mọi thứ ở `main`. stg không bao giờ ghim.
- **Bootstrap EKS (stg, prd):** Terraform của `svp-infra`, root `aws/gitops/<env>` theo mẫu GitOps Bridge: namespace có nhãn Pod Security,
  Argo CD (`argocd/bootstrap.json`, `base/argo-cd.yaml`, `platforms/eks/argo-cd.yaml` bật controller ApplicationSet), AppProject
  (`argocd/project.yaml`), Secret cluster `in-cluster` của Argo CD mang nhãn `svp.io/env`, `svp.io/platform`, `svp.io/node-arch` và annotation
  `svp.io/cluster-values` (giá trị `cluster`), rồi ApplicationSet `svp-bootstrap` sinh `svp-root` từ Secret đó. Mọi file ở đây đọc ở commit
  bootstrap: `gitopsRevision` của env, khoá vắng thì commit của `main` lúc plan. Argo CD và AppProject chỉ đổi khi apply lại root đó.
- **Bootstrap k3d:** `deploy/k8s/gitops.sh` của repo code tạo `svp-root` cùng spec (platform `k3d`, không `cluster`) ở commit đã kiểm, rồi
  chuyển sang theo nhánh.
- **Health của Application:** hai tầng chờ từng wave theo health Lua của `argoproj.io/Application` ở `base/argo-cd.yaml`. Một Application chỉ
  `Healthy` khi `status.sync.comparedTo` đúng `spec.source` (hay `spec.sources`) hiện tại, nó `Synced`, sync gần nhất `Succeeded` và
  `status.health` là `Healthy`. Status còn của spec cũ (ngay sau khi promote đổi image trong `valuesObject`, trước lượt so sánh kế của
  controller) hay chưa `Synced` cho `Progressing`; sync lỗi đã hết lượt thử của đúng source hiện tại cho `Degraded`, của source cũ cho
  `Progressing`. Lua đọc `null` như khoá vắng và không phân biệt `{}` với `[]`, nên bước 1 của check từ chối các giá trị đó trong overlay và
  file image. Nhờ vậy root chỉ `Healthy`, và `argocd/<env>` chỉ `success`, khi bản mới đã chạy. Test không cần cluster:
  `argocd/root/application-health-test.sh` (Docker, jq) chạy Lua đó bằng `argocd admin settings resource-overrides health` của image Argo CD
  mà `base/argo-cd.yaml` ghim.
- **Rollback prd:** promote prd với `stg_ref` cũ mở PR đặt lại `gitopsRevision` cùng image và chart của commit đó; R của `svp-apps` đổi, mọi
  component sync lại bản cũ.

## Lớp nền tảng

Một env chạy trên nhiều nền tảng: stg chạy ở cluster lab `k3d` (cluster GitOps của repo code, runner của `verify.yml`)
và ở Amazon EKS (`eks`); prd chỉ chạy trên `eks`. Khác biệt giữa hai nền tảng nằm ở `platforms/`, không ở `envs/`, nên
`envs/stg/` (bản phát hành, `charts.yaml`, overlay) dùng chung cho cả hai và promote prd không đổi.

- Root nhận giá trị `platform` (`k3d` | `eks`, bắt buộc, không mặc định, như `env`); bootstrap đặt (mục trên).
- Khoá `platforms` đầu `components.json` (ngoài danh sách `components`): mỗi nền tảng nêu `envs` (env chạy trên nền tảng đó: `k3d` chỉ `stg`,
  `eks` cả `stg` và `prd`) và `localHosts: true` khi render của nó được nêu tên lab `*.svp.localhost` (chỉ `k3d`; vắng là không được). Root
  chart không đọc khoá này; check của repo code đọc nó (thiếu hay sai dạng là đỏ), job `diff-preview` cũng render theo nó.
- Trường `platforms` của component trong `components.json`: danh sách nền tảng component chạy; vắng là mọi nền tảng. Chỉ `k3d`:
  `cloudnative-pg`, `plugin-barman-cloud` (Postgres trên EKS là RDS), `loki`, `tempo` (log, trace trên EKS vào CloudWatch Logs, X-Ray). Chỉ
  `eks`: `ack-prometheusservice` (luật và cảnh báo lên AMP), `grafana-operator` (dashboard lên Amazon Managed Grafana), `karpenter` (node cho workload theo pod đang chờ, wave -1
  vì mang CRD của NodePool mà `svp-cluster` render), `aws-load-balancer-controller` (đăng ký pod Envoy vào target group của ALB internal
  qua TargetGroupBinding, wave 1 vì mang CRD của TargetGroupBinding mà `svp-cluster` render). Đường dev (`make k8s-up`) chạy component của
  `k3d`. Không gì trong cluster ghi DNS: bản ghi của env do Terraform của repo hạ tầng tạo.
- `platforms/k3d/`: Secret từ External Secrets với store `kubernetes` (`svp-cluster.yaml`: Secret nguồn ở namespace `svp-secrets` do
  `deploy/k8s/secrets.sh` của repo code ghi); ngoài đó cluster k3d chạy đúng `base/`.
- `platforms/eks/`: Secret từ AWS Secrets Manager với store `aws` của External Secrets ở mọi env (entry `svp/<env>/<entry>`, region và role
  IAM mỗi namespace từ `cluster`; chart `svp-cluster` mở cho controller cổng 443 ra ngoài và agent Pod Identity), node của workload do
  Karpenter cấp (NodePool `default` của `svp-cluster`, giá trị prd ở đây; phần stg giảm ở `envs/stg/svp-cluster.yaml`),
  Kyverno 3 replica trải zone (`kyverno.yaml`), Postgres `external` (RDS, chuỗi kết nối tới địa chỉ instance với `sslmode=verify-full`,
  Secret `rds-ca` từ bundle CA của RDS, `localCA: rds-ca` của bốn service có Postgres), object store `external` (S3 virtual-hosted,
  credential Pod Identity), Kafka `external` (Amazon MSK: Job
  `kafka-init` của `svp-data` chỉ tạo topic và ACL, user do Terraform gắn), Valkey `external` (ElastiCache: host của `REDIS_URL` là
  `cluster.valkeyHost`), không Secret chỉ-k3d của broker và Valkey trong cluster (`externalSecrets.localKafkaValkey: false`), không CA local
  (`localCA: ""` của service không có Postgres, cert của MSK và ElastiCache nối về CA công khai trong root hệ thống), StorageClass `gp3`
  mặc định của
  `svp-cluster` và `gp3` thay `local-path` mà `base/` ghim ở Prometheus, Pyroscope, Envoy sau ALB internal (CloudFront tới
  ALB qua VPC origin; ALB, listener, target group do Terraform tạo): Service `svp-envoy` kiểu `ClusterIP` với TargetGroupBinding
  `svp-envoy`, Gateway `svp` một listener `https` không hostname (ALB không gửi SNI tới target) với Secret `svp-edge-tls` do issuer CA
  riêng `svp-ca` ký cho `<domain>` và `api.<domain>` (ALB không kiểm cert target; trình duyệt thấy cert ACM), HTTPRoute `web` gắn
  `sectionName: https`, NetworkPolicy `envoy` chỉ mở 10443 cho subnet edge (`cluster.edgeCidrs`) và namespace `svp-load` (Job k6 đo trong
  cluster), 19003 (`/ready`, health check của target group) cho subnet edge, gateway lấy IP client từ header `CloudFront-Viewer-Address`
  (`TRUSTED_CLIENT_ADDRESS_HEADER`, không đọc `X-Forwarded-For`), nhãn `elbv2.k8s.aws/pod-readiness-gate-inject: enabled` trên namespace
  `envoy-gateway-system` (root đặt trong `managedNamespaceMetadata` của `envoy-gateway`, chỉ `eks`: pod Envoy mới chỉ Ready khi target group
  của ALB thấy nó khoẻ, nên rollout Envoy không làm cổng vào từ chối request), API server cổng 443, egress theo địa chỉ
  (`externalPeers` của `svp-service`: subnet database cổng 5432
  tới RDS, 9096 tới MSK, 6379 tới ElastiCache, dải S3 của region cổng 443, agent Pod Identity `169.254.170.23` cổng 80; Collector, Job init
  và `svp-ops` tới MSK, ElastiCache theo cùng CIDR), image qua ECR của account (`svp-policy.values.tpl`: policy `svp-registry-mirror` đổi
  image của mọi pod, `svp-images` đọc chữ ký ở ECR, Kyverno đăng nhập bằng Pod Identity), telemetry vào dịch vụ managed của account
  (Prometheus chế độ agent ghi vào AMP, Collector gửi log tới CloudWatch Logs và trace tới X-Ray bằng file đích `k8s-eks.yaml`, luật và
  cảnh báo lên AMP qua ACK rồi tới SNS, dashboard lên Amazon Managed Grafana qua Grafana Operator, canary hỏi AMP bằng SigV4; sơ đồ ở
  [`docs/components.md`](docs/components.md#telemetry-trên-eks)), NetworkPolicy tới endpoint interface trong VPC (`awsEndpointCidrs` là
  `cluster.vpcCidr`), Argo CD tự cài như `base/` cộng ApplicationSet controller và Argo CD Notifications (`argo-cd.yaml`, ADR-0032 của repo code): chỉ root
  `svp-root` (nhãn `svp.io/notify=root` do bootstrap gắn) ghi commit status `argocd/<env>` lên commit của repo này bằng GitHub App
  `svp-argocd-notifier`, Secret qua External Secrets (`externalSecrets.argocdNotifications` của `svp-cluster.yaml`); Telegram khi sync lỗi
  hay Degraded chỉ khi bootstrap gắn chat (annotation `svp.io/telegram-chat-id` của Secret cluster), chat không vào repo.
- File `<name>.yaml` giữ thứ giống nhau trên mọi cluster của nền tảng; mẫu `<name>.values.tpl` giữ thứ cluster quyết định (VPC, tên, bucket,
  zone), render bằng Helm `tpl` trên `.Values.cluster`, mỗi giá trị qua `quote`/`toJson`. Phần mẫu sinh ra đọc sau overlay của env, nên
  overlay không đặt khoá mà mẫu đặt (mẫu thắng). Danh sách trong values bị thay cả danh sách khi ghép (`platformNamespaces` của
  `svp-cluster` nêu đủ mọi phần tử, `envoy.networkPolicy.httpsFrom` của `svp-cluster` cả danh sách ở mẫu). `null` chỉ xoá
  khoá có trong `values.yaml` của chart, nên khoá env của release được làm rỗng (`""`, service đọc như không đặt).

### Hợp đồng giá trị `cluster`

Giá trị phụ thuộc account AWS hay buổi không bao giờ vào git: Terraform của `svp-infra` (`aws/envs/<env>`) xuất output `cluster_values`,
root `aws/gitops/<env>` ghi nó vào annotation `svp.io/cluster-values` của Secret cluster, ApplicationSet `svp-bootstrap` đặt thành giá trị
`cluster` của `svp-root`, tầng 1 chuyển nguyên khối cho tầng 2. `argocd/apps/values.yaml` để `cluster: {}`; file nào trong
git đặt `cluster` thì check đỏ. Root kiểm từng khoá trước khi render mẫu (thiếu hay sai dạng thì dừng, nêu tên khoá). Check của repo này
render nền tảng `eks` bằng fixture `deploy/ci/cluster-values.example.yaml` của repo code (tên `.example`, CIDR tài liệu, account toàn số 0).

| Khoá | Dạng | Ai dùng (mẫu ở `platforms/eks/`) |
| --- | --- | --- |
| `name` | tên cluster EKS | nhãn ngoài `cluster` của Prometheus agent (`kube-prometheus-stack`), `clusterName` của `aws-load-balancer-controller`, `settings.clusterName` và hàng đợi `settings.interruptionQueue` (`<name>-karpenter`) của `karpenter`, `karpenter.clusterName` (role node, tag discovery) của `svp-cluster` |
| `region` | region AWS | SigV4 của remote write (`kube-prometheus-stack`), `rules.amp.region`, `dashboards.grafana.region` của `svp-observability`, `sigv4Region` của `canaryPrometheus` (`gateway`, `web`), `SVP_OTELCOL_REGION` của `otel-collector`, `region` của LBC, `AWS_REGION` của `karpenter`, `externalSecrets.aws.region` của `svp-cluster`, endpoint S3 vùng và `S3_REGION` của `video-service`, `media-worker`, `UPLOAD_ORIGIN` của `web` |
| `vpcId` | `vpc-…` | `vpcId` của LBC (pod không đọc IMDS) |
| `vpcCidr` | CIDR | `nodeSubnet` của `svp-cluster`, `nodeSubnet` của `svp-observability`, `awsEndpointCidrs` của `svp-cluster`, `svp-observability` (NetworkPolicy tới endpoint interface), `externalPeers.s3` (cổng 443, endpoint interface MediaConvert, SQS) của `media-worker`, `TRUSTED_PROXY_CIDRS` của `gateway` |
| `serviceCidr` | CIDR, địa chỉ mạng `….0/12`–`/24` | `kubeAPIServiceIP` (địa chỉ `.1`) của `svp-cluster` |
| `dbCidrs` | danh sách CIDR | `postgres.external.cidrs`, `kafka.external.cidrs`, `valkey.external.cidrs` của `svp-data`, `postgres.external.cidrs`, `kafka.external.cidrs` của `svp-observability`, `externalPeers.postgres` (cổng 5432) của `user-service`, `video-service`, `engagement-service`, `feed-service`, `externalPeers.kafka` (cổng 9096) của bốn service đó cùng `media-worker`, `externalPeers.valkey` (cổng 6379) của `gateway`, `feed-service`, `web` |
| `domain` | tên miền | `dnsNames` `<domain>`, `api.<domain>` của listener `https` và `apexHost`, `wildcardHost` `*.<domain>` (chỉ chart chưa có `listeners` đọc) của `svp-cluster`; host route `web`, `api.<domain>` của `gateway`; `APP_ORIGIN` của `web` |
| `edgeTargetGroupArn` | ARN target group (`arn:aws:elasticloadbalancing:<region>:<account>:targetgroup/<tên>/<id>`) | `envoy.targetGroupArn` (TargetGroupBinding `svp-envoy`) của `svp-cluster` |
| `edgeCidrs` | danh sách CIDR (subnet edge của ALB internal) | `envoy.networkPolicy.httpsFrom` (cổng 10443, cùng namespace `svp-load`) và `envoy.networkPolicy.healthCheck.from` (cổng 19003) của `svp-cluster` |
| `rdsAddress` | tên miền | `postgres.external.host` của `svp-data`; `externalSecrets.postgres` (`<rdsAddress>:5432`, host của mọi `DATABASE_URL`) của `svp-cluster` |
| `uploadsBucket` | tên bucket | `S3_UPLOADS_BUCKET` của `video-service`, `media-worker`; `UPLOAD_ORIGIN` `https://<uploadsBucket>.s3.<region>.amazonaws.com` của `web` |
| `mediaBucket` | tên bucket | `S3_MEDIA_BUCKET` của `video-service`, `media-worker` |
| `mediaDomain` | tên `*.cloudfront.net` | `MEDIA_PUBLIC_BASE_URL` `https://<mediaDomain>` của `gateway` (đường là key, không thêm `/media` như path-style của k3d), `MEDIA_ORIGIN` của `web` |
| `kafkaBrokers` | chuỗi `host:9096,host:9096,…`, một mục mỗi broker, không khoảng trắng (bootstrap SCRAM của MSK) | `KAFKA_BROKERS` của `user-service`, `video-service`, `engagement-service`, `feed-service`, `media-worker`; `kafka.brokers` của `svp-data` (Job `kafka-init`, `svp-ops`); `SVP_OTELCOL_KAFKA_BROKERS` của `otel-collector` |
| `valkeyHost` | tên miền, không cổng (primary endpoint của ElastiCache) | `externalSecrets.valkey` (`<valkeyHost>:6379`, host của `REDIS_URL`) của `svp-cluster`; `valkey.host` của `svp-data` (`svp-ops`) |
| `s3Cidrs` | danh sách CIDR | `externalPeers.s3` (cổng 443, cùng agent Pod Identity) của `video-service`, `media-worker` |
| `ecrRegistry` | host registry ECR (`<account>.dkr.ecr.<region>.amazonaws.com`) | `registryMirror.rules` (đích của sáu tiền tố) và `releaseRegistry` của `svp-policy` |
| `ampWorkspaceId` | `ws-…` | `rules.amp.workspaceId` của `svp-observability` (workspace mà ACK ghi luật vào) |
| `ampEndpoint` | `https://aps-workspaces.<region>.amazonaws.com/workspaces/ws-…/`, có `/` cuối | URL remote write của `kube-prometheus-stack` (cộng `api/v1/remote_write`), `SVP_OTELCOL_AMP_ENDPOINT` của `otel-collector`, `dashboards.grafana.ampEndpoint` của `svp-observability`, `address` của `canaryPrometheus` (`gateway`, `web`; bỏ `/` cuối) |
| `logGroup` | `/svp/<env>/otel` | `SVP_OTELCOL_LOG_GROUP` của `otel-collector` |
| `grafanaUrl` | `https://g-….grafana-workspace.<region>.amazonaws.com`, không `/` cuối | `dashboards.grafana.url` của `svp-observability` (CR `Grafana` của Grafana Operator) |
| `alarmTopicArn` | ARN topic SNS `svp-<env>-alarms` | `rules.amp.alarmTopicArn` của `svp-observability` (đích của `AlertManagerDefinition`) |
| `mediaconvertQueueArn` | ARN queue MediaConvert `svp-<env>` (`arn:aws:mediaconvert:<region>:<account>:queues/svp-<env>`) | `MEDIACONVERT_QUEUE_ARN` của `media-worker` |
| `mediaconvertRoleArn` | ARN role IAM `svp-<env>-mediaconvert` (role MediaConvert dùng đọc, ghi S3) | `MEDIACONVERT_ROLE_ARN` của `media-worker` |
| `transcodeEventsQueueUrl` | URL hàng đợi SQS `svp-<env>-transcode-events` (`https://sqs.<region>.amazonaws.com/<account>/…`) | `TRANSCODE_EVENTS_QUEUE_URL` của `media-worker` |
| `externalSecretsRoles` | map đúng năm namespace `svp`, `svp-data`, `svp-obs`, `keda`, `argocd` → ARN role IAM | `externalSecrets.aws.roles` của `svp-cluster`: role SecretStore của từng namespace (thiếu namespace thì render dừng) |

Thêm khoá thì sửa cả bốn nơi: output `cluster_values` của `svp-infra`, mẫu và phép kiểm khoá của root ở đây (`argocd/apps/templates/applications.yaml`)
cùng bảng này, fixture của repo code, bảng hợp đồng của ADR-0034.

## Ai duyệt gì

- `envs/stg/` (overlay, `charts.yaml`, `images/` của stg) **không có Code Owner**: PR promote stg do bot mở sau mỗi lượt build trên
  `main`, tự merge khi `gitops-ok` xanh: GitHub App `svp-gitops-promoter` cho repo code, `svp-web-promoter` cho `svp-frontend`. Check giới hạn
  file mỗi bot được đổi theo tác giả PR (mục Check).
- Mọi file khác (`base/`, `envs/prd/`, `argocd/`, `.github/`, file ở gốc) có Code Owner `anhnvcoder` (`CODEOWNERS`): PR do bot hay
  Renovate mở cần người học duyệt; PR của chính người học merge bằng bypass của ruleset `owners` (có bản ghi bypass), check của ruleset
  `main` vẫn bắt buộc.
- Ruleset `main`: cấm xoá và force push nhánh mặc định, mọi thay đổi qua PR, chỉ squash merge, lịch sử thẳng, check bắt buộc
  `gitops-ok` của app GitHub Actions, không ai bypass. Ruleset `owners`: PR đổi file có chủ phải được Code Owner duyệt; vai admin bypass ở chế độ `pull_request`.
- Ruleset `tags`: mọi tag (`~ALL`) cấm tạo, sửa, xoá, chỉ vai admin bypass (chế độ `always`, chế độ `pull_request` chỉ áp cho ruleset
  nhánh). Repo này không dùng tag; Argo CD phân giải `targetRevision` tên ngắn bằng ref đầu tiên trùng tên, cả tag, nên tag `main` do token
  của App (`contents: write`) bị lộ tạo ra có thể thành bản được deploy.
- Ba ruleset tạo và sửa bằng Terraform ở `github/rulesets.tf` của repo `svp-infra`; `actor_id` 5 của `owners` và `tags` là vai admin của
  repo, kiểm lại sau mỗi `apply`.
  Resource: [`github_repository_ruleset`](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_ruleset).

## Promote

- **stg:** tự động. Job `promote` của `images.yml` (repo code, bước shell của workflow) ghi khối `image` của `envs/stg/images/` cho mỗi
  service vừa ký ở lượt đó (sáu service Go của repo code) và `envs/stg/charts.yaml` (commit của lượt build; lượt có commit là tổ tiên thật
  của `revision` đang có bị từ chối, nên chart không lùi) trên nhánh `bot/promote-stg`, mở hay cập nhật PR và bật auto-merge. CI của
  `svp-frontend` làm như vậy cho riêng `envs/stg/images/web.yaml` trên nhánh `bot/promote-stg-web`.
- **prd:** cả bộ. Dispatch promote prd ở repo code (`-f promote_prd=true [-f stg_ref=<main|SHA đủ 40 hex>]`) nhận `stg_ref`, `main` hay
  một commit trên `main` của repo này, và chép **giá trị khối `image` của cả bảy file `envs/stg/images/` cùng ba khoá của
  `envs/stg/charts.yaml`** ở commit đó sang cùng file dưới `envs/prd/` (comment của file prd giữ nguyên), cùng `gitopsRevision: <stg_ref>`
  (commit đủ) trong `envs/prd/charts.yaml`, trên nhánh `bot/promote-prd`; PR không auto-merge. **Bằng chứng stg:** job từ chối `stg_ref` không
  có commit status `argocd/stg` trạng thái `success` (Argo CD Notifications của stg ghi khi mọi Application Healthy ở commit đó), nên prd chỉ
  nhận bộ stg đã đồng bộ xong. Cổng vào prd còn hai lượt duyệt: người học duyệt environment `promote-prd` của `svp-backend` (admin không bypass,
  trước khi job lấy khoá App), rồi người học (Code Owner) duyệt PR prd ở đây. Không có promote prd theo từng service.
- **Rollback prd:** dispatch promote prd với `stg_ref` là một commit cũ hơn trên `main` có `argocd/stg` `success` (attestation `vuln` quá 48 giờ
  thì rescan trước); PR đặt lại cả `gitopsRevision`, nên `base/`, `platforms/` cũng về bản của commit đó.
- **Ngoại lệ khởi tạo:** ở commit đầu, `envs/prd/images/` và `envs/prd/charts.yaml` là đúng bộ của `envs/stg/` (bảy bản phát hành
  build ở `6ca2d8a795dd`, chart ở commit `main` của repo code lúc tách). Sau đó `envs/prd/` đổi bằng promote prd.

## Check

`.github/workflows/check.yml` checkout repo này và repo code ở `CHECKER_COMMIT` (ghim trong chính workflow, đổi bằng PR có Code Owner;
Renovate đề xuất commit mới), rồi chạy `deploy/ci/gitops-check.sh` của commit đó (job `gitops`, chỉ quyền `contents: read`, không secret,
check tổng `gitops-ok`):

1. Cây: `envs/` đúng stg và prd; `charts.yaml` đúng ba khoá (prd thêm được `gitopsRevision`: commit trên `main` của repo này có
   `argocd/apps`), `revision` là commit trên `main` của repo code, hai giá trị dẫn xuất tính lại từ commit đó; mỗi `envs/<env>/images/<svc>.yaml` chỉ khối `image`, repository là `<imagePrefix><svc>` của một nguồn phát hành có `<svc>`
   trong bảng nguồn (`sources.json` của chart `svp-policy`) ở `revision` của env; overlay và file image không đặt `null`, `{}` hay `[]` ở bất kỳ
   độ sâu nào (health Lua của Application không thấy khác biệt đó); lớp nền tảng theo khoá `platforms` của `components.json`.
   Luật tác giả hẹp, viết từ bảng nguồn: PR của bot `<promoter>[bot]` một nguồn chỉ đổi `envs/{stg,prd}/images/<svc>.yaml` với `<svc>` của
   nguồn đó; bot của repo code đổi thêm `envs/{stg,prd}/charts.yaml` và mọi file `envs/prd/images/` (promote prd chép cả bộ, web gồm);
   không bot nào xoá file; bot khác (Renovate) không đổi gì dưới `envs/`. PR của người không bị giới hạn ở đây (Code Owner duyệt).
2. Render root như Argo CD theo env × nền tảng của khoá `platforms` × kiến trúc node: tầng 1 `argocd/root` ra đúng `svp-apps` ở R, tầng 2
   `argocd/apps` với values đó; env ghim render tầng 2 trên `git archive` của commit ghim cùng `envs/<env>/` của cây, mọi file values đọc ở
   commit ghim; `valuesObject` của mỗi Application bằng overlay < image của `envs/<env>/` trên cây < phần mẫu sinh ra, gộp như Helm; mọi
   `targetRevision` vào repo này là tên đầy đủ, mọi nguồn của repo này trong một Application cùng một revision.
3. Render chart của repo code ở `revision` của env với `base/`, `platforms/` và overlay; External Secrets qua kubeconform; render của nền
   tảng không `localHosts` không nêu `svp.localhost`.
4. Mọi image ghim digest (policy Kyverno CLI `images-pinned`); overlay không đổi version image của render nó chồng lên.
5. File image đổi so với base: chữ ký, attestation `vuln`, provenance env đòi; có provenance thì tag là 12 hex của commit nó nêu.

Logic nằm hết ở script đó, nên cùng một lệnh chạy được trên máy với một bản clone; PR ở đây không đổi được thứ kiểm nó trừ khi sửa
`check.yml`, file có Code Owner. `gitops-ok` là check duy nhất của workflow này mà ruleset `main` đòi, nên các job trước nó đổi tên hay thêm mà
không đụng ruleset. Repo public và PR từ fork chạy workflow với cây của fork, nên:

- Không `pull_request_target`, không `workflow_run`: PR không bao giờ chạy với token ghi hay secret.
- Mọi job chỉ đọc (`contents: read`; riêng `changes` chỉ `pull-requests: read`) và không job nào có secret: job `zizmor` đưa `GITHUB_TOKEN` chỉ đọc cho
  zizmor, công cụ đọc dữ liệu public bằng nó; `diff-preview` đọc cả hai repo và các repo chart ẩn danh.
- Mọi action là của GitHub và ghim SHA đầy đủ của commit: tag bị dời sang code khác không đổi gì ở đây.
- `actions/checkout` không để token trong `.git/config` (`persist-credentials: false`).
- Giá trị người ngoài điều khiển (tên nhánh, tiêu đề) vào script qua `env`, không qua `${{ }}`.

Job `changes` chia PR theo vùng qua danh sách file của API (quyền `pull-requests: read`, không checkout): PR chỉ đổi tài liệu (`.md`,
`LICENSE`) bỏ qua `gitops` và `diff-preview`, PR không đổi `.github/` bỏ qua `zizmor`; `docs` luôn chạy; đổi `Makefile` hay `check.yml`,
push và dispatch thì chạy hết (file đổi tên xét cả tên cũ; API liệt kê thiếu file thì cũng chạy hết). `gitops-ok` nhận đúng các skip đó, skip khác là đỏ. PR của bot luôn đổi `envs/` nên luôn chạy `gitops`.

Không so bản ghi stg, không luật tổ tiên (tag image không cần là tổ tiên của `revision`), không clone `svp-frontend`. Chạy trên máy, từ gốc
một bản clone đủ lịch sử của repo code (`origin/main` đã fetch):

```sh
deploy/ci/gitops-check.sh <thư mục clone svp-gitops> [<commit base>]
deploy/ci/gitops-check-test.sh <thư mục clone svp-gitops>
```

### Diff preview

Job `diff-preview` của cùng workflow, chỉ ở PR (push `main` không có gì để so), **ngoài `gitops-ok`** (đỏ không chặn merge), quyền `contents: read`, không secret, không
comment vào PR (việc đó cần token ghi): chạy [argocd-diff-preview](https://github.com/dag-andersen/argocd-diff-preview) (image ghim tag + digest, Renovate theo dõi,
chạy bằng `docker run`, để mọi action của workflow này là của GitHub). Root ở đây là hai chart Helm nên job render cả hai tầng của mỗi env
trên mỗi nền tảng của khoá `platforms` như `gitops-check.sh`: `argocd/root` (node amd64: kiến trúc chỉ đổi plugin traffic router của Argo Rollouts; `cluster` của `eks` là fixture
`deploy/ci/cluster-values.example.yaml` của commit checker), rồi `argocd/apps` của cùng phía với `valuesObject` của `svp-apps`; chỉ
Application của tầng 2 vào công cụ (`svp-apps` chỉ hiện lại chúng). Hai phía: commit merge của PR và cha đầu của nó (nhánh base lúc merge); phía chưa có `argocd/root`
render thẳng `argocd/apps`. Env ghim `gitopsRevision` hiện như khi ghim ở commit của phía đó (`gitops-ok` render nó ở commit ghim). Tên mỗi Application mang tiền tố `<env>-<nền tảng>-` (`stg-k3d-gateway`,
`prd-eks-gateway`): ba root cùng tên component, không có tiền tố thì công cụ đánh số chúng theo thứ tự file. Công cụ dựng cluster kind tạm trên runner, cài Argo CD theo chart và version của
`argocd/bootstrap.json`, trỏ nguồn values và env của repo này sang commit của từng phía (phía PR là `refs/pull/<số>/merge`), giữ nguyên nguồn
chart (chart upstream, chart repo code ở `revision`), rồi lấy manifest Argo CD render; mọi repo đọc ẩn danh qua HTTPS như trên cluster.

Đọc kết quả: tóm tắt của job `diff-preview` (trang lượt chạy, mục Summary) là diff manifest theo Application, chỉ Application có manifest
đổi; đổi `base/` hiện ở mọi env và nền tảng đọc file đó, đổi overlay hay file image chỉ ở env đó. Không có diff khi bước công cụ lỗi: đọc log
của bước `argocd-diff-preview` (Application không render được nêu tên ở đó). Diff dài hơn 65 536 ký tự bị cắt.

### Docs

Job `docs` của cùng workflow, **trong `gitops-ok`**, quyền `contents: read`, chạy `make docs-check`: markdownlint-cli2 theo
`.markdownlint.yaml`, rồi lychee `--offline --include-fragments` (link tương đối và anchor heading; link ra ngoài không kiểm). Hai công cụ
chạy trong image ghim tag + digest (`MARKDOWNLINT_IMAGE`, `LYCHEE_IMAGE` trong `Makefile`, Renovate theo dõi), không mạng. Mặc định kiểm mọi
`.md` git theo dõi và file mới chưa theo dõi; `make docs-check DOCS='<file hay glob>'` thu hẹp.

### zizmor

Job `zizmor` của cùng workflow, **trong `gitops-ok`**, chạy khi PR đổi `.github/` (job `changes`), khi push và dispatch: lint bảo mật workflow bằng
[zizmor](https://docs.zizmor.sh/) từ image chính thức ghim tag + digest (`ZIZMOR_IMAGE` trong `env` của `check.yml`, Renovate theo dõi),
`--persona=regular` trên cả repo (mount chỉ đọc) như repo code chạy (`make zizmor` ở đó), mọi finding là đỏ (mã thoát 11 đến 14) và hiện thành annotation trên PR. Token
`GITHUB_TOKEN` chỉ đọc của job bật các audit online (commit mạo danh, action có lỗ hổng). Finding giữ có chủ đích ghi ở
`.github/zizmor.yml` (`rules.<id>.ignore`), mỗi mục một comment lý do; hiện chưa có mục nào nên chưa có file. Trên máy chỉ chạy offline,
không token:

```sh
env -u DOCKER_DEFAULT_PLATFORM docker run --rm --user "$(id -u):$(id -g)" --env=ZIZMOR_OFFLINE=true --network=none \
  -v "$PWD:/src:ro" --workdir /src "$(sed -n 's/^  ZIZMOR_IMAGE: //p' .github/workflows/check.yml)" \
  --persona=regular --no-progress --color=never --cache-dir /tmp/zizmor .
```

### Scorecard

`.github/workflows/scorecard.yml` chạy [OpenSSF Scorecard](https://github.com/ossf/scorecard) khi push `main`, hằng tuần và khi luật bảo
vệ nhánh kiểu cũ đổi; không phải check của PR. Kết quả công khai ở API Scorecard
([viewer](https://scorecard.dev/viewer/?uri=github.com/anhnvcoder/svp-gitops), `publish_results: true`, huy hiệu) và vào code scanning. Kiểm ghim,
quyền token, ruleset, mẫu workflow nguy hiểm và các [check khác](https://github.com/ossf/scorecard/blob/main/docs/checks.md); check
Branch-Protection đọc ruleset bằng `GITHUB_TOKEN` nên không cần `repo_token`. Check Code-Review luôn thấp (lab một
người, PR không đòi duyệt): ngoại lệ có chủ đích.

Muốn API nhận kết quả thì file theo "Workflow Restrictions" của API Scorecard (README của `ossf/scorecard-action`, mã ở
`api/app/server/verify_workflow.go` của `ossf/scorecard-infra`): không `env` hay `defaults` ở mức workflow và ở job, không quyền ghi ở mức
workflow, `id-token: write` chỉ ở job Scorecard, không container hay service, một nhãn runner Ubuntu do GitHub host (`ubuntu-latest` hay
`ubuntu-YY.MM`, 22.04 trở lên), và chỉ `actions/checkout`, `actions/upload-artifact`, `github/codeql-action/upload-sarif`,
`ossf/scorecard-action`, `step-security/harden-runner` làm step của job đó, mỗi step là một `uses:` (không step `run:`). API nhận hay không thì hiện
ở log của step Scorecard. Mọi action ghim SHA đầy đủ của commit; checkout không để token trong `.git/config`.

## Tiêu đề PR

`main` chỉ nhận squash merge nên tiêu đề PR thành tiêu đề commit. Workflow `pr-title.yml` (job `pr-title`, tách khỏi `check.yml` để sửa
tiêu đề không chạy lại check, không quyền, không checkout, không code của PR; tiêu đề vào script qua `env`, không qua `${{ }}`) kiểm tiêu đề theo [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)
bằng regex của bash, chung cho bốn repo có CI:

```text
^(feat|fix|chore|docs|refactor|test|ci|build|perf|revert)(\([^)]+\))?!?: .+|^Revert ".+"$
```

Ngữ pháp, không danh sách scope: tiêu đề của bot qua nguyên dạng (`chore(stg): …` của PR promote stg, `chore(prd): …` của promote prd,
`chore(deps): …`, `fix(deps): …` của Renovate), PR revert của stg cũng vậy (nút Revert của GitHub cho `Revert "<tiêu đề>"`, hay
`revert: <tiêu đề>`). Bộ tiêu đề thử đạt và hỏng chạy trước tiêu đề của PR ở mỗi lượt, nên regex hỏng thì mọi PR đỏ.

## Nguồn gốc

Commit khởi tạo dựng từ một commit `main` của repo code (SHA đầy đủ ghi trong message của commit đó), không giữ lịch sử (lịch sử cũ
còn ở repo code):

| Repo code | Ở đây |
| --- | --- |
| `deploy/k8s/values/` | `base/` |
| khối `image` của `deploy/k8s/values/services/<svc>.yaml` | `envs/<env>/images/<svc>.yaml` |
| `deploy/k8s/envs/` | `envs/` |
| `deploy/argocd/` | `argocd/` |
| `argocd_chart_version` của `deploy/k8s/gitops.sh` | `argocd/bootstrap.json` |
| symlink `files/svp-cluster-values.yaml`, `files/otelcol-k8s-config.yaml` | `podSecurityVersion`, `collectorConfigSha256` của `envs/<env>/charts.yaml` |

Thiết kế và lý do: [ADR-0025](https://github.com/anhnvcoder/svp-backend/blob/main/docs/adr/0025-gitops-config-repo.md),
[ADR-0024](https://github.com/anhnvcoder/svp-backend/blob/main/docs/adr/0024-multi-environment.md) §8,
[ADR-0040](https://github.com/anhnvcoder/svp-backend/blob/main/docs/adr/0040-sigstore-bundle-actions-attest.md) (chữ ký, attestation, provenance).

## Đóng góp

Quy ước chung (ngôn ngữ, tài liệu, Git, repo public) ở [`CONTRIBUTING.md`](https://github.com/anhnvcoder/.github/blob/main/CONTRIBUTING.md)
của `anhnvcoder/.github`; luật riêng của repo ở [`AGENTS.md`](AGENTS.md). Mọi thay đổi vào `main` đi qua pull request có `gitops-ok` xanh.

## Giấy phép

[Apache-2.0](LICENSE).
