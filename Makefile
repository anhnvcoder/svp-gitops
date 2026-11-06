# Entry point of the documentation check. `make help` lists the targets.

.DEFAULT_GOAL := help
.PHONY: help docs-check

help: ## List the targets
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

# markdownlint-cli2 (style), then lychee --offline --include-fragments (relative links and heading anchors; other sites
# are not followed: a check that depends on the network fails for reasons outside the change). Pinned images, no
# network, repository read-only: a link that leaves it (to plans/, which is no repository's) is an error on purpose.
# DOCS narrows the files; the default is every Markdown file git tracks plus untracked ones. Both tools always run.
# renovate: datasource=docker depName=davidanson/markdownlint-cli2
MARKDOWNLINT_IMAGE := davidanson/markdownlint-cli2:v0.24.0@sha256:70ead7c0352d22d04bbe612cd96b54ec591538d8f4626cafe391bb2ecf3639ca
# renovate: datasource=docker depName=lycheeverse/lychee
LYCHEE_IMAGE := lycheeverse/lychee:0.24.2@sha256:e2d19e57cf6ab037026f20b8e449a1f30d9d7f81eef4194763aab2eab20bd28d
# set -f keeps the globs of DOCS whole: the tools expand them (with **), sh does not and would drop the files at the top.
DOCS ?=
docs-check: ## markdownlint-cli2 + lychee --offline on the Markdown (DOCS='<files or globs>' narrows; pinned images, no network)
	@if [ -n '$(DOCS)' ]; then set -f; set -- $(DOCS); set +f; \
	else set --; for f in $$(git ls-files --cached --others --exclude-standard '*.md'); do [ -f "$$f" ] && set -- "$$@" "$$f"; done; fi; \
	rc=0; \
	env -u DOCKER_DEFAULT_PLATFORM docker run --rm --network none -v "$(CURDIR):/repo:ro" --workdir /repo \
		$(MARKDOWNLINT_IMAGE) "$$@" || rc=1; \
	env -u DOCKER_DEFAULT_PLATFORM docker run --rm --network none -v "$(CURDIR):/repo:ro" --workdir /repo \
		$(LYCHEE_IMAGE) --offline --include-fragments "$$@" || rc=1; \
	exit $$rc
