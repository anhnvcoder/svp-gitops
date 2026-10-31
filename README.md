# svp-gitops

Cấu hình triển khai của nền tảng video ngắn, repo code [svp-backend](https://github.com/anhnvcoder/svp-backend): values
Helm gốc, khác biệt và bản phát hành của từng môi trường, manifest của Argo CD. Argo CD của mỗi cluster chỉ đọc repo này (và chart
của repo code ở đúng commit repo này ghim); cái gì chạy ở stg, prd chỉ đổi được qua pull request vào đây. Code, test, Dockerfile, chart
(`deploy/helm/*`) và CI build, quét, ký image ở repo code; riêng web client build, quét, ký ở repo của nó,
[svp-frontend](https://github.com/anhnvcoder/svp-frontend). Trong lúc chuyển web sang đó, bản web build từ repo code vẫn được nhận; mỗi
`envs/<env>/images/web.yaml` ghi bản nào đang chạy.

Repo public: **không có secret, token, khoá hay id App nào ở đây**. Values chỉ nêu tên Secret; giá trị nằm ở cluster (lab: `.env` của
máy chạy, qua External Secrets Operator) hay ở AWS Secrets Manager (prd).

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
envs/<env>/                 stg và prd
  <component>.yaml          overlay: chỉ phần khác gốc, comment đầu file nói vì sao
  svp-policy.yaml           bật kiểm build provenance của Kyverno (requireProvenance: true)
  charts.yaml               commit của repo code mà chart của env chạy, cùng hai giá trị dẫn xuất từ commit đó
  images/<svc>.yaml         7 file, mỗi file chỉ khối image (repository, tag, digest) của bản phát hành
argocd/
  project.yaml              AppProject svp và default (đã khoá)
  bootstrap.json            chart Argo CD: repo, chart, version, values (base/argo-cd.yaml)
  apps/                     chart app-of-apps; components.json là danh sách component
.github/workflows/check.yml check của mỗi pull request và push main, check tổng gitops-ok
.github/rulesets/           ruleset main, owners và tags (nhập bằng tay, xem dưới)
CODEOWNERS, renovate.json
```

Thứ tự ghép values của một Application: `values.yaml` của chart → `base/` → `platforms/<platform>/<name>.yaml` → `envs/<env>/<name>.yaml`
→ `envs/<env>/images/<name>.yaml` → phần mẫu `platforms/<platform>/<name>.values.tpl` sinh ra (`helm.valuesObject`, Argo CD đọc sau mọi
file). Chart `argocd/apps` từ chối lúc render (Argo CD báo `ComparisonError` trên root): env không có thư mục, thiếu `charts.yaml` hay có
khoá khác ba khoá của nó, overlay không trùng tên component, overlay của release `svp-service` có `image`, `canary`, `httpRoute.name`,
thiếu một trong 7 file `images/`, file `images/` có khoá ngoài `image`; `platform` không đặt hay khác `k3d`, `eks`, trường `platforms` của
`components.json` sai, file của nền tảng không trùng component chạy trên nền tảng đó, không phải map YAML hay đặt `cluster`, file hay mẫu của
release `svp-service` có `image`, `canary`, `httpRoute.name`, `cluster` thiếu khoá hay sai dạng (mục dưới). `charts` là tên dành riêng,
không component nào được mang.

## Lớp nền tảng

Một env chạy trên nhiều nền tảng: stg chạy ở cluster lab `k3d` (cluster GitOps của repo code, runner của `verify.yml`, nơi ghi bản ghi stg)
và ở Amazon EKS (`eks`, giai đoạn 7); prd chỉ chạy trên `eks`. Khác biệt giữa hai nền tảng nằm ở `platforms/`, không ở `envs/`, nên
`envs/stg/` (bản phát hành, `charts.yaml`, overlay) dùng chung cho cả hai và promote prd không đổi.

- Root nhận giá trị `platform` (`k3d` | `eks`, bắt buộc, không mặc định, như `env`); bootstrap đặt (`deploy/k8s/gitops.sh` của repo code).
- Trường `platforms` của component trong `components.json`: danh sách nền tảng component chạy; vắng là mọi nền tảng. Chỉ `k3d`:
  `cloudnative-pg`, `plugin-barman-cloud` (Postgres trên EKS là RDS). Chỉ `eks`: `aws-load-balancer-controller` (NLB trước Envoy từ Service
  của Envoy, wave 1 vì Gateway `svp` chỉ `Programmed` khi Service có địa chỉ), `external-dns` (bản ghi Route 53 cho host của HTTPRoute gắn
  vào Gateway `svp`, wave 2). Đường dev (`make k8s-up`) chạy component của `k3d`.
- `platforms/k3d/` chỉ có README: cluster k3d chạy đúng `base/`, root với `platform=k3d` render đúng các Application như trước khi có lớp này.
- `platforms/eks/`: Postgres `external` (RDS qua Service `ExternalName`), object store `external` (S3 virtual-hosted, credential Pod
  Identity), StorageClass `gp3` mặc định của `svp-cluster` và `gp3` thay `local-path` mà `base/` ghim ở Loki, Prometheus, Tempo, Pyroscope
  (Redpanda không ghim class, nhận class mặc định), issuer ACME Let's Encrypt production (DNS-01 Route 53), Service NLB của Envoy và
  NetworkPolicy của nó, nhãn `elbv2.k8s.aws/pod-readiness-gate-inject: enabled` trên namespace `envoy-gateway-system` (root đặt trong
  `managedNamespaceMetadata` của `envoy-gateway`, chỉ `eks`: pod Envoy mới chỉ Ready khi NLB thấy target khoẻ, nên rollout Envoy không
  làm cổng vào từ chối kết nối), API server cổng 443, egress theo địa chỉ (`externalPeers` của `svp-service`: subnet RDS cổng 5432, dải S3 của region
  cổng 443, agent Pod Identity `169.254.170.23` cổng 80).
- File `<name>.yaml` giữ thứ giống nhau trên mọi cluster của nền tảng; mẫu `<name>.values.tpl` giữ thứ cluster quyết định (VPC, tên, bucket,
  zone), render bằng Helm `tpl` trên `.Values.cluster`, mỗi giá trị qua `quote`/`toJson`. Phần mẫu sinh ra đọc sau overlay của env, nên
  overlay không đặt khoá mà mẫu đặt (mẫu thắng). Danh sách trong values bị thay cả danh sách khi ghép (`platformNamespaces` của
  `svp-cluster` nêu đủ mọi phần tử); cờ của ExternalDNS là map `extraArgs` để mẫu thêm cờ mà không xoá cờ của `base/`. `null` chỉ xoá
  khoá có trong `values.yaml` của chart, nên khoá env của release được làm rỗng (`""`, service đọc như không đặt).

### Hợp đồng giá trị `cluster`

Giá trị phụ thuộc account AWS hay buổi không bao giờ vào git: Terraform của `svp-infra` (`aws/envs/<env>`) xuất output `cluster_values`,
script buổi ghi ra file, bootstrap đặt thành giá trị `cluster` của root `svp-root`. `argocd/apps/values.yaml` để `cluster: {}`; file nào trong
git đặt `cluster` thì check đỏ. Root kiểm từng khoá trước khi render mẫu (thiếu hay sai dạng thì dừng, nêu tên khoá). Check của repo này
render nền tảng `eks` bằng fixture `deploy/ci/cluster-values.example.yaml` của repo code (tên `.example`, CIDR tài liệu, account toàn số 0).

| Khoá | Dạng | Ai dùng (mẫu ở `platforms/eks/`) |
| --- | --- | --- |
| `name` | tên cluster EKS | `clusterName` của `aws-load-balancer-controller`, `txtOwnerId` của `external-dns` |
| `region` | region AWS | `region` của LBC, `AWS_DEFAULT_REGION` của ExternalDNS, `tls.acme.region` của `svp-cluster`, endpoint S3 vùng và `S3_REGION` của `video-service`, `media-worker`, `UPLOAD_ORIGIN` của `web` |
| `vpcId` | `vpc-…` | `vpcId` của LBC (pod không đọc IMDS) |
| `vpcCidr` | CIDR | `nodeSubnet` và `envoy.networkPolicy.healthCheckCIDR` của `svp-cluster`, `nodeSubnet` của `svp-observability`, `TRUSTED_PROXY_CIDRS` của `gateway` |
| `serviceCidr` | CIDR, địa chỉ mạng `….0/12`–`/24` | `kubeAPIServiceIP` (địa chỉ `.1`) của `svp-cluster` |
| `dbCidrs` | danh sách CIDR | `postgres.external.cidrs` của `svp-data`, `svp-observability`, `externalPeers.postgres` (cổng 5432) của `user-service`, `video-service`, `engagement-service`, `feed-service` |
| `domain` | tên miền | `apexHost` (web), `wildcardHost` `*.<domain>` của `svp-cluster`; host route `web`, `api.<domain>` của `gateway`; `APP_ORIGIN` của `web`; `domainFilters` của ExternalDNS |
| `hostedZoneId` | `Z…` | `tls.acme.hostedZoneId` của `svp-cluster`, `--zone-id-filter` của ExternalDNS |
| `acmeEmail` | email | `tls.acme.email` của `svp-cluster` |
| `rdsAddress` | tên miền | `postgres.external.host` của `svp-data` |
| `uploadsBucket` | tên bucket | `S3_UPLOADS_BUCKET` của `video-service`, `media-worker`; `UPLOAD_ORIGIN` `https://<uploadsBucket>.s3.<region>.amazonaws.com` của `web` |
| `mediaBucket` | tên bucket | `S3_MEDIA_BUCKET` của `video-service`, `media-worker` |
| `mediaDomain` | tên `*.cloudfront.net` | `MEDIA_PUBLIC_BASE_URL` `https://<mediaDomain>` của `gateway` (đường là key, không thêm `/media` như path-style của k3d), `MEDIA_ORIGIN` của `web` |
| `s3Cidrs` | danh sách CIDR | `externalPeers.s3` (cổng 443, cùng agent Pod Identity) của `video-service`, `media-worker` |

Thêm khoá thì sửa cả bốn nơi: output `cluster_values` của `svp-infra`, mẫu và phép kiểm khoá của root ở đây (`argocd/apps/templates/applications.yaml`)
cùng bảng này, fixture của repo code, bảng hợp đồng của ADR-0034.

## Ai duyệt gì

- `envs/stg/` (overlay, `charts.yaml`, `images/` của stg) **không có Code Owner**: PR promote stg do bot mở sau mỗi lượt build trên
  `main`, tự merge khi `gitops-ok` xanh: GitHub App `svp-gitops-promoter` cho repo code, `svp-web-promoter` cho `svp-frontend`. Check giới hạn
  file mỗi bot được đổi theo tác giả PR (mục Check).
- Mọi file khác (`base/`, `envs/prd/`, `argocd/`, `.github/`, file ở gốc) có Code Owner `anhnvcoder` (`CODEOWNERS`): PR do bot hay
  Renovate mở cần người học duyệt; PR của chính người học merge bằng bypass của ruleset `owners` (có bản ghi bypass), check của ruleset
  `main` vẫn bắt buộc.
- Ruleset `main`: cấm xoá và force push nhánh mặc định, mọi thay đổi qua PR, check bắt buộc `gitops-ok` của app GitHub Actions, không
  ai bypass. Ruleset `owners`: PR đổi file có chủ phải được Code Owner duyệt; vai admin bypass ở chế độ `pull_request`.
- Ruleset `tags`: mọi tag (`~ALL`) cấm tạo, sửa, xoá, chỉ vai admin bypass (chế độ `always`, chế độ `pull_request` chỉ áp cho ruleset
  nhánh). Repo này không dùng tag; Argo CD phân giải `targetRevision` tên ngắn bằng ref đầu tiên trùng tên, cả tag, nên tag `main` do token
  của App (`contents: write`) bị lộ tạo ra có thể thành bản được deploy.
- Ba file ở `.github/rulesets/` là bản để nhập (`gh api -X POST repos/anhnvcoder/svp-gitops/rulesets --input .github/rulesets/main.json`),
  không có hiệu lực khi chỉ nằm trong repo; `actor_id` 5 của `owners.json` và `tags.json` là vai admin của repo, kiểm lại sau khi nhập.
  Schema: [REST API ruleset của repository](https://docs.github.com/en/rest/repos/rules#create-a-repository-ruleset).

## Promote

- **stg:** tự động. Job `promote` của `images.yml` (repo code) ghi `envs/stg/images/` của service vừa build và `envs/stg/charts.yaml`
  (commit của lượt build, không bao giờ lùi) trên nhánh `bot/promote-stg`, mở PR và bật auto-merge. CI của `svp-frontend` làm như vậy cho
  riêng `envs/stg/images/web.yaml` trên nhánh `bot/promote-stg-web`; file web đã là bản của `svp-frontend` thì promote của repo code để nguyên.
- **prd:** cả bộ. Dispatch promote prd ở repo code nhận một bản ghi triển khai stg (Deployment `stg` trên repo này, ghi sau khi
  phép kiểm trên stg qua) và chép **cả bảy digest cùng `charts.yaml`** của bản ghi đó sang `envs/prd/`; PR do bot mở, người học duyệt.
  Check của PR prd đòi cả bộ khớp payload của một bản ghi stg `success`. Không có promote prd theo từng service.
- **Rollback prd:** dispatch promote prd với một bản ghi stg cũ hơn (attestation `vuln` quá 48 giờ thì rescan trước).
- **Ngoại lệ khởi tạo:** ở commit đầu, `envs/prd/images/` và `envs/prd/charts.yaml` là đúng bộ của `envs/stg/` (bảy bản phát hành
  build ở `6ca2d8a795dd`, chart ở commit `main` của repo code lúc tách), vì khi đó chưa có bản ghi stg nào để chép từ. Từ lần promote prd
  đầu tiên, `envs/prd/` chỉ đổi theo bản ghi stg.

## Check

`.github/workflows/check.yml` checkout repo này và repo code ở `CHECKER_COMMIT` (ghim trong chính workflow, đổi bằng PR có Code Owner;
Renovate đề xuất commit mới), rồi chạy `deploy/ci/gitops-check.sh` của commit đó: render mọi env × nền tảng (stg trên `k3d` và `eks`, prd
trên `eks`) × kiến trúc node với chart của repo code ở `revision` của env, quy tắc của `charts.yaml` và `images/`, image của chart upstream ghim digest, render prd và nền tảng `eks` không còn
`svp.localhost`, chữ ký, attestation và provenance của bản phát hành đã đổi. Quy tắc của `images/` theo nguồn phát hành (bảng nguồn của
chart `svp-policy` ở `revision`): bản của repo code có tag là `revision` hay tổ tiên của nó (image không mới hơn chart); bản của `svp-frontend`
có tag là commit trên `main` của `svp-frontend`, đọc từ bản clone ẩn danh đủ lịch sử (`--filter=blob:none`) mà check tự làm theo URL
của nguồn trong bảng ở `revision` (bảng cũ ghi URL trước khi đổi tên repo, GitHub chuyển hướng về repo hiện tại; vì vậy workflow không
checkout repo web và không đặt `SVP_SOURCE_DIR_*`). Trên PR do bot mở, mỗi bot chỉ đổi được file image của nguồn mình (bot của repo code thêm
`envs/{stg,prd}/charts.yaml` và `envs/prd/images/`), không xoá file nào dưới `envs/`. Chạy trên máy, từ gốc một bản clone đủ lịch sử của repo code:

```sh
deploy/ci/gitops-check.sh <thư mục clone svp-gitops> [<commit base>]
deploy/ci/gitops-check-test.sh <thư mục clone svp-gitops>
```

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
[ADR-0027](https://github.com/anhnvcoder/svp-backend/blob/main/docs/adr/0027-slsa-build-provenance.md).
