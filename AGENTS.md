# svp-gitops: hướng dẫn cho agent

File này theo định dạng [AGENTS.md](https://agents.md): luật làm việc cho mọi agent.

Repo là cấu hình triển khai của nền tảng video ngắn (repo code [svp-backend](https://github.com/anhnvcoder/svp-backend)): values Helm
gốc, khác biệt và bản phát hành của từng môi trường, manifest của Argo CD. Argo CD của mỗi cluster chỉ đọc repo này; cái gì chạy ở
stg, prd chỉ đổi được qua pull request vào đây. Đọc trước: [`README.md`](README.md) (cấu trúc, lớp nền tảng, hợp đồng giá trị
`cluster`, promote, check). Thiết kế chung của lab nằm ở `docs/` của repo code (bản clone `<workspace>/backend`); đổi một quyết định
đã chốt thì đề xuất kèm ADR ở đó.

## Cây thư mục

- `base/`: values gốc của mọi môi trường (`services/<svc>.yaml` không có khối `image`).
- `platforms/<k3d|eks>/`: khác biệt của nền tảng; thứ phụ thuộc account hay buổi là mẫu `*.values.tpl`, không bao giờ là giá trị trong git.
- `envs/<stg|prd>/`: overlay (chỉ phần khác gốc), `charts.yaml` (commit của repo code mà chart chạy), `images/<svc>.yaml` (bản phát hành).
- `argocd/`: AppProject, `bootstrap.json`, root hai tầng: `root/` (tầng 1, ra Application `svp-apps` ở revision ghim hay nhánh,
  đọc `envs/<env>/`) và chart app-of-apps `apps/` (tầng 2, danh sách component ở `components.json`).
- `.github/workflows/check.yml`, `pr-title.yml`, `scorecard.yml`, `CODEOWNERS`, `renovate.json`.
- `Makefile` (`make docs-check`), `.markdownlint.yaml`, `lychee.toml`, `LICENSE` (Apache-2.0).

## Quy ước

Quy ước chung (ngôn ngữ, tài liệu timeless, ADR, comment, Git, repo public, phụ thuộc): [`CONTRIBUTING.md` của `anhnvcoder/.github`](https://github.com/anhnvcoder/.github/blob/main/CONTRIBUTING.md); dưới đây chỉ luật riêng của repo này.

- **Repo public: không secret, token, khoá hay id App.** Values chỉ nêu tên Secret; giá trị nằm ở cluster hay AWS Secrets Manager.
  File nào trong git đặt `cluster` thì check đỏ.
- **Ngôn ngữ viết:** file `.md` viết tiếng Việt.
- **File bot ghi, không sửa tay:** `envs/stg/images/*.yaml` và `envs/stg/charts.yaml` do bot promote ghi (nhánh `bot/promote-stg`,
  `bot/promote-stg-web`); `envs/prd/images/*.yaml` và `envs/prd/charts.yaml` do promote prd chép từ stg (nhánh `bot/promote-prd`).
  Đổi bản phát hành qua promote, không chép tay.
- **Code Owner:** mọi file có chủ `anhnvcoder` trừ `envs/stg/` (bot tự merge khi `gitops-ok` xanh); `envs/stg/svp-policy.yaml` vẫn
  có chủ, vì không bot nào được tắt kiểm provenance. PR đụng file có chủ cần người học duyệt.
- **Git:** mọi thay đổi vào `main` đi qua PR có `gitops-ok` xanh, chỉ squash merge; không tạo tag (ruleset `tags` cấm).
- **Tiêu đề PR** thành tiêu đề commit, theo Conventional Commits (`<type>[(<scope>)][!]: <mô tả>`, type `feat fix chore docs refactor
  test ci build perf revert`, hay `Revert "<tiêu đề>"`); `pr-title.yml` kiểm, regex và bộ thử ở mục "Tiêu đề PR" của `README.md`.

## Kiểm tra

- Check bắt buộc `gitops-ok` (`.github/workflows/check.yml`): checkout repo code ở `CHECKER_COMMIT` (ghim trong workflow) rồi chạy
  `deploy/ci/gitops-check.sh` của nó: cây thư mục và luật tác giả của bot, render root hai tầng (`argocd/root` rồi `argocd/apps`)
  theo env × nền tảng × kiến trúc node, render chart của repo code ở `revision` của env, mọi image ghim digest, chữ ký, attestation
  và provenance của image đổi.
- Chạy trên máy từ gốc bản clone đủ lịch sử của repo code: `deploy/ci/gitops-check.sh <thư mục clone svp-gitops> [<commit base>]`;
  `make helm-check` của backend render mọi chart với overlay của bản clone này.
- `make docs-check`: markdownlint-cli2 và lychee `--offline` trên mọi `.md` (image ghim digest, không mạng); `DOCS='<file hay glob>'`
  thu hẹp. Job `docs` của `check.yml` chạy đúng lệnh này và nằm trong `gitops-ok`; sửa `.md` thì chạy trước khi mở PR.
- Job `diff-preview` chỉ ở PR, ngoài `gitops-ok`: diff manifest theo Application ở tóm tắt của lượt chạy.
- Job `zizmor` (lint bảo mật workflow, image ghim `ZIZMOR_IMAGE`) nằm trong `gitops-ok`: sửa workflow thì chạy lệnh offline ở mục
  "zizmor" của `README.md` trước khi mở PR; finding giữ có chủ đích vào `.github/zizmor.yml` kèm lý do. Trên máy không truyền token.
- `scorecard.yml` (OpenSSF Scorecard) chạy trên `main` và hằng tuần, không phải check của PR; giữ đúng luật "Workflow Restrictions" ở đầu file.

## An toàn cloud

AI không chạy lệnh nào chạm tài khoản AWS/GCP hay cluster cloud, kể cả lệnh chỉ đọc; soạn lệnh để người học tự chạy, như mục "An toàn
cloud và chuỗi cung ứng" của `AGENTS.md` backend. `kubectl`/`helm` chỉ vào cluster k3d, luôn ghi `--context k3d-<tên>`.
