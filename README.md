# svp-gitops

Cấu hình triển khai của nền tảng video ngắn [short-video-platform](https://github.com/anhnvcoder/short-video-platform): values
Helm gốc, khác biệt và bản phát hành của từng môi trường, manifest của Argo CD. Argo CD của mỗi cluster chỉ đọc repo này (và chart
của repo code ở đúng commit repo này ghim); cái gì chạy ở stg, prd chỉ đổi được qua pull request vào đây. Code, test, Dockerfile, chart
(`deploy/helm/*`) và CI build, quét, ký image ở repo code.

Repo public: **không có secret, token, khoá hay id App nào ở đây**. Values chỉ nêu tên Secret; giá trị nằm ở cluster (lab: `.env` của
máy chạy, qua External Secrets Operator) hay ở AWS Secrets Manager (prd).

## Cấu trúc

```text
base/                       values gốc của mọi môi trường; đường dev (make k8s-up của repo code) chỉ đọc lớp này
  <component>.yaml          values của chart upstream (cả argo-rollouts-amd64.yaml theo kiến trúc node)
  argo-cd.yaml              values của chính Argo CD
  services/<svc>.yaml       values của 7 release chart svp-service, không có khối image
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

Thứ tự ghép values của một Application: `values.yaml` của chart → `base/` → `envs/<env>/<name>.yaml` → `envs/<env>/images/<name>.yaml`.
Chart `argocd/apps` từ chối lúc render (Argo CD báo `ComparisonError` trên root): env không có thư mục, thiếu `charts.yaml` hay có khoá
khác ba khoá của nó, overlay không trùng tên component, overlay của release `svp-service` có `image`, `canary`, `httpRoute.name`,
thiếu một trong 7 file `images/`, file `images/` có khoá ngoài `image`. `charts` là tên dành riêng, không component nào được mang.

## Ai duyệt gì

- `envs/stg/` (overlay, `charts.yaml`, `images/` của stg) **không có Code Owner**: PR promote stg do bot (GitHub App
  `svp-gitops-promoter`) mở sau mỗi lượt build trên `main` của repo code, tự merge khi `gitops-ok` xanh.
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
  (commit của lượt build, không bao giờ lùi) trên nhánh `bot/promote-stg`, mở PR và bật auto-merge.
- **prd:** cả bộ. Dispatch promote prd ở repo code nhận một bản ghi triển khai stg (Deployment `stg` trên repo này, ghi sau khi
  phép kiểm trên stg qua) và chép **cả bảy digest cùng `charts.yaml`** của bản ghi đó sang `envs/prd/`; PR do bot mở, người học duyệt.
  Check của PR prd đòi cả bộ khớp payload của một bản ghi stg `success`. Không có promote prd theo từng service.
- **Rollback prd:** dispatch promote prd với một bản ghi stg cũ hơn (attestation `vuln` quá 48 giờ thì rescan trước).
- **Ngoại lệ khởi tạo:** ở commit đầu, `envs/prd/images/` và `envs/prd/charts.yaml` là đúng bộ của `envs/stg/` (bảy bản phát hành
  build ở `6ca2d8a795dd`, chart ở commit `main` của repo code lúc tách), vì khi đó chưa có bản ghi stg nào để chép từ. Từ lần promote prd
  đầu tiên, `envs/prd/` chỉ đổi theo bản ghi stg.

## Check

`.github/workflows/check.yml` checkout repo này và repo code ở `CHECKER_COMMIT` (ghim trong chính workflow, đổi bằng PR có Code Owner;
Renovate đề xuất commit mới), rồi chạy `deploy/ci/gitops-check.sh` của commit đó: render mọi env × kiến trúc node với chart của repo
code ở `revision` của env, quy tắc của `charts.yaml` và `images/` (image không mới hơn chart), image của chart upstream ghim digest,
render prd không còn `svp.localhost`, chữ ký, attestation và provenance của bản phát hành đã đổi. Chạy trên máy, từ gốc một bản clone đủ
lịch sử của repo code:

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

Thiết kế và lý do: [ADR-0025](https://github.com/anhnvcoder/short-video-platform/blob/main/docs/adr/0025-gitops-config-repo.md),
[ADR-0024](https://github.com/anhnvcoder/short-video-platform/blob/main/docs/adr/0024-multi-environment.md) §8,
[ADR-0027](https://github.com/anhnvcoder/short-video-platform/blob/main/docs/adr/0027-slsa-build-provenance.md).
