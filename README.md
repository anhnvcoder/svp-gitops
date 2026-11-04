# svp-gitops

Cấu hình triển khai của nền tảng video ngắn: values Helm, bản phát hành của từng môi trường và manifest Argo CD, do Argo CD của mỗi cluster đọc.

## Mục lục

- [Bối cảnh](#bối-cảnh)
- [Cài đặt](#cài-đặt)
- [Sử dụng](#sử-dụng)
- [Cấu trúc](#cấu-trúc)
- [Lớp nền tảng](#lớp-nền-tảng)
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
máy chạy, qua External Secrets Operator) hay ở AWS Secrets Manager (prd).

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
  charts.yaml               commit của repo code mà chart của env chạy, cùng hai giá trị dẫn xuất từ commit đó
  images/<svc>.yaml         7 file, mỗi file chỉ khối image (repository, tag, digest) của bản phát hành
argocd/
  project.yaml              AppProject svp và default (đã khoá)
  bootstrap.json            chart Argo CD: repo, chart, version, values (base/argo-cd.yaml)
  apps/                     chart app-of-apps; components.json là danh sách component
.github/workflows/check.yml check của mỗi pull request và push main, check tổng gitops-ok
.github/workflows/pr-title.yml  tiêu đề PR theo Conventional Commits (mục Tiêu đề PR)
.github/workflows/scorecard.yml OpenSSF Scorecard của repo (mục Check)
CODEOWNERS, renovate.json
Makefile                    docs-check (markdownlint-cli2 và lychee); cấu hình ở .markdownlint.yaml, lychee.toml
LICENSE                     Apache-2.0
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

Một env chạy trên nhiều nền tảng: stg chạy ở cluster lab `k3d` (cluster GitOps của repo code, runner của `verify.yml`)
và ở Amazon EKS (`eks`); prd chỉ chạy trên `eks`. Khác biệt giữa hai nền tảng nằm ở `platforms/`, không ở `envs/`, nên
`envs/stg/` (bản phát hành, `charts.yaml`, overlay) dùng chung cho cả hai và promote prd không đổi.

- Root nhận giá trị `platform` (`k3d` | `eks`, bắt buộc, không mặc định, như `env`); bootstrap đặt (`deploy/k8s/gitops.sh` của repo code).
- Khoá `platforms` đầu `components.json` (ngoài danh sách `components`): mỗi nền tảng nêu `envs` (env chạy trên nền tảng đó: `k3d` chỉ `stg`,
  `eks` cả `stg` và `prd`) và `localHosts: true` khi render của nó được nêu tên lab `*.svp.localhost` (chỉ `k3d`; vắng là không được). Root
  chart không đọc khoá này; check của repo code đọc nó (thiếu hay sai dạng là đỏ), job `diff-preview` cũng render theo nó.
- Trường `platforms` của component trong `components.json`: danh sách nền tảng component chạy; vắng là mọi nền tảng. Chỉ `k3d`:
  `cloudnative-pg`, `plugin-barman-cloud` (Postgres trên EKS là RDS). Chỉ `eks`: `aws-load-balancer-controller` (NLB trước Envoy từ Service
  của Envoy, wave 1 vì Gateway `svp` chỉ `Programmed` khi Service có địa chỉ), `external-dns` (bản ghi Route 53 cho host của HTTPRoute gắn
  vào Gateway `svp`, wave 2). Đường dev (`make k8s-up`) chạy component của `k3d`.
- `platforms/k3d/` chỉ có README: cluster k3d chạy đúng `base/`, nên root với `platform=k3d` render đúng các Application của `base/`.
- `platforms/eks/`: Postgres `external` (RDS qua Service `ExternalName`), object store `external` (S3 virtual-hosted, credential Pod
  Identity), StorageClass `gp3` mặc định của `svp-cluster` và `gp3` thay `local-path` mà `base/` ghim ở Loki, Prometheus, Tempo, Pyroscope
  (Redpanda không ghim class, nhận class mặc định), issuer ACME Let's Encrypt production (DNS-01 Route 53), Service NLB của Envoy và
  NetworkPolicy của nó, nhãn `elbv2.k8s.aws/pod-readiness-gate-inject: enabled` trên namespace `envoy-gateway-system` (root đặt trong
  `managedNamespaceMetadata` của `envoy-gateway`, chỉ `eks`: pod Envoy mới chỉ Ready khi NLB thấy target khoẻ, nên rollout Envoy không
  làm cổng vào từ chối kết nối), API server cổng 443, egress theo địa chỉ (`externalPeers` của `svp-service`: subnet RDS cổng 5432, dải S3 của region
  cổng 443, agent Pod Identity `169.254.170.23` cổng 80), Argo CD Notifications (`argo-cd.yaml`, ADR-0032 của repo code): chỉ root
  `svp-root` (nhãn `svp.io/notify=root` do bootstrap gắn) ghi commit status `argocd/<env>` lên commit của repo này bằng GitHub App
  `svp-argocd-notifier`, Secret qua External Secrets (`externalSecrets.argocdNotifications` của `svp-cluster.yaml`); Telegram khi sync lỗi
  hay Degraded chỉ khi bootstrap gắn chat từ `.env`, chat không vào repo.
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
  `envs/stg/charts.yaml`** ở commit đó sang cùng file dưới `envs/prd/` (comment của file prd giữ nguyên), trên nhánh `bot/promote-prd`;
  PR không auto-merge. Cổng vào prd là hai bước: người học duyệt environment `promote-prd` của `svp-backend` (admin không bypass, trước khi
  job lấy khoá App), rồi người học (Code Owner) duyệt PR prd ở đây. Không có bản ghi triển khai stg: `stg_ref` chỉ bảo đảm bộ đó từng nằm trên
  `main` của `envs/stg/`, không bảo đảm stg đã chạy và smoke qua với đúng bộ đó; cổng là hai lượt duyệt. Không có promote prd theo từng service.
- **Rollback prd:** dispatch promote prd với `stg_ref` là một commit cũ hơn trên `main` (attestation `vuln` quá 48 giờ thì rescan trước).
- **Ngoại lệ khởi tạo:** ở commit đầu, `envs/prd/images/` và `envs/prd/charts.yaml` là đúng bộ của `envs/stg/` (bảy bản phát hành
  build ở `6ca2d8a795dd`, chart ở commit `main` của repo code lúc tách). Sau đó `envs/prd/` đổi bằng promote prd.

## Check

`.github/workflows/check.yml` checkout repo này và repo code ở `CHECKER_COMMIT` (ghim trong chính workflow, đổi bằng PR có Code Owner;
Renovate đề xuất commit mới), rồi chạy `deploy/ci/gitops-check.sh` của commit đó (job `gitops`, chỉ quyền `contents: read`, không secret,
check tổng `gitops-ok`):

1. Cây: `envs/` đúng stg và prd; `charts.yaml` đúng ba khoá, `revision` là commit trên `main` của repo code, hai giá trị dẫn xuất tính lại
   từ commit đó; mỗi `envs/<env>/images/<svc>.yaml` chỉ khối `image`, repository là `<imagePrefix><svc>` của một nguồn phát hành có `<svc>`
   trong bảng nguồn (`sources.json` của chart `svp-policy`) ở `revision` của env; lớp nền tảng theo khoá `platforms` của `components.json`.
   Luật tác giả hẹp, viết từ bảng nguồn: PR của bot `<promoter>[bot]` một nguồn chỉ đổi `envs/{stg,prd}/images/<svc>.yaml` với `<svc>` của
   nguồn đó; bot của repo code đổi thêm `envs/{stg,prd}/charts.yaml` và mọi file `envs/prd/images/` (promote prd chép cả bộ, web gồm);
   không bot nào xoá file; bot khác (Renovate) không đổi gì dưới `envs/`. PR của người không bị giới hạn ở đây (Code Owner duyệt).
2. Render root `argocd/apps` theo env × nền tảng của khoá `platforms` × kiến trúc node; mọi `targetRevision` vào repo này là tên đầy đủ.
3. Render chart của repo code ở `revision` của env với `base/`, `platforms/` và overlay; External Secrets qua kubeconform; render của nền
   tảng không `localHosts` không nêu `svp.localhost`.
4. Mọi image ghim digest (policy Kyverno CLI `images-pinned`); overlay không đổi version image của render nó chồng lên.
5. File image đổi so với base: chữ ký, attestation `vuln`, provenance env đòi; có provenance thì tag là 12 hex của commit nó nêu.

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

Job `diff-preview` của cùng workflow, chỉ ở PR, **ngoài `gitops-ok`** (đỏ không chặn merge), quyền `contents: read`, không secret, không
comment vào PR: chạy [argocd-diff-preview](https://github.com/dag-andersen/argocd-diff-preview) (image ghim tag + digest, Renovate theo dõi,
chạy bằng `docker run`, để mọi action của workflow này là của GitHub). Root ở đây là chart Helm nên job render root của mỗi env trên mỗi nền tảng của
khoá `platforms` (node amd64; `cluster` của `eks` là fixture `deploy/ci/cluster-values.example.yaml` của commit checker) cho hai phía: commit
merge của PR và cha đầu của nó (nhánh base lúc merge). Tên mỗi Application mang tiền tố `<env>-<nền tảng>-` (`stg-k3d-gateway`,
`prd-eks-gateway`): ba root cùng tên component. Công cụ dựng cluster kind tạm trên runner, cài Argo CD theo chart và version của
`argocd/bootstrap.json`, trỏ nguồn values của repo này sang commit của từng phía (phía PR là `refs/pull/<số>/merge`), giữ nguyên nguồn
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
`--persona=regular` trên cả repo như repo code chạy (`make zizmor` ở đó), mọi finding là đỏ và hiện thành annotation trên PR. Token
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
([viewer](https://scorecard.dev/viewer/?uri=github.com/anhnvcoder/svp-gitops)) và vào code scanning. Check Code-Review luôn thấp (lab một
người, PR không đòi duyệt): ngoại lệ có chủ đích. Muốn API nhận kết quả thì file theo luật "Workflow Restrictions" ghi ở đầu file.

## Tiêu đề PR

`main` chỉ nhận squash merge nên tiêu đề PR thành tiêu đề commit. Workflow `pr-title.yml` (job `pr-title`, tách khỏi `check.yml` để sửa
tiêu đề không chạy lại check, không quyền, không checkout) kiểm tiêu đề theo [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)
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
