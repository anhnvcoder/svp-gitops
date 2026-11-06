#!/usr/bin/env bash
# shellcheck disable=SC2016 # $names in single quotes are jq variables and the inner shell's
# application-health-test.sh: the test of the health check of argoproj.io/Application in base/argo-cd.yaml, which the
# root's two levels wait on and whose Healthy root makes Argo CD Notifications write argocd/<env> success. Each case is
# one Application with a status as the controller writes it; Argo CD's own Lua engine assesses it, without network and
# without a cluster. Needs docker (image pulled when missing) and jq. Exit 0 when every case gets its expected status.
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd -P)
values=$repo/base/argo-cd.yaml

# The image of every Argo CD component: global.image, repository and the digest of tag (version@digest).
image=$(awk '
  /^[^ #]/ { g = ($0 ~ /^global:/) }
  g && $1 == "repository:" { r = $2 }
  g && $1 == "tag:" { t = $2 }
  END { if (r != "" && t ~ /@sha256:/) print r "@" substr(t, index(t, "@") + 1) }
' "$values")
[ -n "$image" ] || { echo "global.image of $values holds no repository and tag version@digest" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/cases"

# The ConfigMap argocd-cm with the one key: the block scalar of base/argo-cd.yaml, two spaces less indented.
key=resource.customizations.health.argoproj.io_Application
{
  printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: argocd-cm\n  namespace: argocd\ndata:\n  %s: |\n' "$key"
  awk -v k="    $key: |" '
    $0 == k { f = 1; next }
    f && /^      / { print substr($0, 3); next }
    f && /^ *$/ { print ""; next }
    f { exit }
  ' "$values"
} >"$tmp/cm.yaml"
grep -q 'return hs' "$tmp/cm.yaml" || { echo "$values has no $key" >&2; exit 1; }

r1=1111111111111111111111111111111111111111
r2=2222222222222222222222222222222222222222
# One source like svp-apps: a promote changes an image in valuesObject.
src() {
  jq -nc --arg tag "$1" '{repoURL: "https://github.com/anhnvcoder/svp-gitops.git", targetRevision: "refs/heads/main",
    path: "argocd/apps", helm: {valuesObject: {env: "stg", envFiles: {images: {gateway: {image: {tag: $tag}}}}}}}'
}
# Two sources like a component of argocd/apps: a chart of the code repository at a revision, values from svp-gitops.
srcs() {
  jq -nc --arg rev "$1" '[{repoURL: "https://github.com/anhnvcoder/svp-backend.git", targetRevision: $rev,
    path: "deploy/helm/svp-data", helm: {releaseName: "svp-data", skipCrds: false, valueFiles: ["$values/base/svp-data.yaml"]}},
    {repoURL: "https://github.com/anhnvcoder/svp-gitops.git", targetRevision: "refs/heads/main", ref: "values"}]'
}
new=$(src v2) old=$(src v1) newm=$(srcs "$r2") oldm=$(srcs "$r1")
# The same sources as the controller writes them back: Go's JSON leaves out skipCrds false, and keeps an empty
# source (repoURL "") beside the sources of a multi-source Application.
newm_go=$(jq -c 'map(del(.helm.skipCrds?))' <<<"$newm")

cases=()
# case NAME EXPECTED FILTER: an Application (spec.source $new unless FILTER sets otherwise) with the status FILTER sets.
case_() {
  cases+=("$1 $2")
  jq -n --argjson new "$new" --argjson old "$old" --argjson newm "$newm" --argjson oldm "$oldm" \
    --argjson newm_go "$newm_go" --arg r1 "$r1" --arg r2 "$r2" \
    '{apiVersion: "argoproj.io/v1alpha1", kind: "Application", metadata: {name: "svp-apps", namespace: "argocd"},
      spec: {project: "svp", destination: {server: "https://kubernetes.default.svc", namespace: "argocd"}, source: $new}}
     | '"$3" >"$tmp/cases/$1.json"
}
ok='.status.operationState = {phase: "Succeeded", syncResult: {revision: $r2, source: $new}}'
case_ no-status Progressing '.'
case_ sync-running Progressing '.status = {operationState: {phase: "Running", message: "waiting for completion of hook batch/Job/pg-bootstrap"},
  sync: {status: "OutOfSync", revision: $r2, comparedTo: {source: $new}}}'
case_ spec-not-compared-yet Progressing '.status = {sync: {status: "Synced", revision: $r1, comparedTo: {source: $old}},
  health: {status: "Healthy"}, operationState: {phase: "Succeeded", syncResult: {revision: $r1, source: $old}}}'
case_ compared-synced-healthy Healthy '.status = {sync: {status: "Synced", revision: $r2, comparedTo: {source: $new}},
  health: {status: "Healthy"}} | '"$ok"
case_ compared-synced-healthy-no-operation Healthy '.status = {sync: {status: "Synced", revision: $r2, comparedTo: {source: $new}},
  health: {status: "Healthy"}}'
case_ compared-synced-health-progressing Progressing '.status = {sync: {status: "Synced", revision: $r2,
  comparedTo: {source: $new}}, health: {status: "Progressing", message: "Waiting for rollout to finish"}} | '"$ok"
case_ compared-synced-health-degraded Degraded '.status = {sync: {status: "Synced", revision: $r2, comparedTo: {source: $new}},
  health: {status: "Degraded"}} | '"$ok"
case_ synced-operation-failed Degraded '.status = {sync: {status: "Synced", revision: $r2, comparedTo: {source: $new}},
  health: {status: "Healthy"}, operationState: {phase: "Failed", message: "job pg-bootstrap failed",
  syncResult: {revision: $r2, source: $new}}}'
case_ synced-operation-error Degraded '.status = {sync: {status: "Synced", revision: $r2, comparedTo: {source: $new}},
  health: {status: "Healthy"}, operationState: {phase: "Error", message: "one or more objects failed to apply"}}'
case_ outofsync-new-revision Progressing '.status = {sync: {status: "OutOfSync", revision: $r2, comparedTo: {source: $new}},
  health: {status: "Healthy"}, operationState: {phase: "Succeeded", syncResult: {revision: $r1, source: $new}}}'
case_ outofsync-same-revision-new-spec Progressing '.status = {sync: {status: "OutOfSync", revision: $r2,
  comparedTo: {source: $new}}, health: {status: "Healthy"},
  operationState: {phase: "Succeeded", syncResult: {revision: $r2, source: $old}}}'
case_ outofsync-after-sync-of-same-spec Progressing '.status = {sync: {status: "OutOfSync", revision: $r2,
  comparedTo: {source: $new}}, health: {status: "Healthy"}} | '"$ok"
case_ outofsync-failed-for-current-spec Degraded '.status = {sync: {status: "OutOfSync", revision: $r2,
  comparedTo: {source: $new}}, health: {status: "Healthy"}, operationState: {phase: "Failed",
  message: "retried 10 times", syncResult: {revision: $r2, source: $new}}}'
case_ outofsync-failed-for-older-spec Progressing '.status = {sync: {status: "OutOfSync", revision: $r2,
  comparedTo: {source: $new}}, health: {status: "Healthy"}, operationState: {phase: "Failed",
  syncResult: {revision: $r2, source: $old}}}'
case_ outofsync-failed-for-older-revision Progressing '.status = {sync: {status: "OutOfSync", revision: $r2,
  comparedTo: {source: $new}}, health: {status: "Healthy"}, operationState: {phase: "Failed",
  syncResult: {revision: $r1, source: $new}}}'
# Synced, no automated sync comes: a failed sync of an older source says nothing of the current one, one of the current
# source at an older revision (a commit that did not change this Application) still stands.
case_ synced-failed-for-older-spec Progressing '.status = {sync: {status: "Synced", revision: $r2,
  comparedTo: {source: $new}}, health: {status: "Healthy"}, operationState: {phase: "Failed",
  message: "job pg-bootstrap failed", syncResult: {revision: $r1, source: $old}}}'
case_ synced-failed-for-older-revision Degraded '.status = {sync: {status: "Synced", revision: $r2,
  comparedTo: {source: $new}}, health: {status: "Healthy"}, operationState: {phase: "Failed",
  message: "job pg-bootstrap failed", syncResult: {revision: $r1, source: $new}}}'
case_ comparison-unknown Progressing '.status = {sync: {status: "Unknown", comparedTo: {source: $new}},
  health: {status: "Healthy"}} | '"$ok"
case_ values-false-is-a-value Progressing '.spec.source.helm.valuesObject.canary = false
  | .status = {sync: {status: "Synced", revision: $r2, comparedTo: {source: $new}}, health: {status: "Healthy"}}'
case_ sources-compared-as-go-writes-them Healthy '.spec |= (del(.source) | .sources = $newm)
  | .status = {sync: {status: "Synced", revisions: [$r2, $r1], comparedTo: {source: {repoURL: ""}, sources: $newm_go}},
    health: {status: "Healthy"}, operationState: {phase: "Succeeded",
    syncResult: {revisions: [$r2, $r1], sources: $newm_go, source: {repoURL: ""}}}}'
case_ sources-not-compared-yet Progressing '.spec |= (del(.source) | .sources = $newm)
  | .status = {sync: {status: "Synced", revisions: [$r1, $r1], comparedTo: {sources: $oldm}}, health: {status: "Healthy"}}'
# A promote to prd moves the revision of every component's values source: a component whose render it leaves as is is
# Synced in the first comparison and gets no sync, so its last sync stays one of the older sources.
case_ sources-succeeded-for-older-pin Healthy '.spec |= (del(.source) | .sources = ($newm | .[1].targetRevision = $r2))
  | .status = {sync: {status: "Synced", revisions: [$r2, $r2], comparedTo: {sources: ($newm_go | .[1].targetRevision = $r2)}},
    health: {status: "Healthy"}, operationState: {phase: "Succeeded",
    syncResult: {revisions: [$r2, $r1], sources: ($newm_go | .[1].targetRevision = $r1)}}}'
case_ sources-failed-for-older-pin Progressing '.spec |= (del(.source) | .sources = ($newm | .[1].targetRevision = $r2))
  | .status = {sync: {status: "Synced", revisions: [$r2, $r2], comparedTo: {sources: ($newm_go | .[1].targetRevision = $r2)}},
    health: {status: "Healthy"}, operationState: {phase: "Failed", message: "job pg-bootstrap failed",
    syncResult: {revisions: [$r2, $r1], sources: ($newm_go | .[1].targetRevision = $r1)}}}'
case_ sources-failed-for-current-revisions Degraded '.spec |= (del(.source) | .sources = $newm)
  | .status = {sync: {status: "OutOfSync", revisions: [$r2, $r1], comparedTo: {sources: $newm_go}},
    health: {status: "Healthy"}, operationState: {phase: "Failed", syncResult: {revisions: [$r2, $r1], sources: $newm}}}'

# The image runs as its own user (UID 999): the fixtures must be readable by any user, mktemp -d makes the folder 0700.
chmod -R a+rX "$tmp"

# One container for every case; each prints its name, then the command's STATUS: and MESSAGE: lines.
out=$(env -u DOCKER_DEFAULT_PLATFORM docker run --rm --network none -v "$tmp:/w:ro" --entrypoint bash "$image" -c '
  for f in /w/cases/*.json; do
    echo "CASE: $(basename "$f" .json)"
    argocd admin settings resource-overrides health "$f" --argocd-cm-path /w/cm.yaml 2>/dev/null || echo "STATUS: error"
  done')

fail=0
for c in "${cases[@]}"; do
  name=${c% *} want=${c#* }
  got=$(awk -v n="$name" '$0 == "CASE: " n { f = 1; next } /^CASE: / { f = 0 } f && /^STATUS: / { print $2 }' <<<"$out")
  msg=$(awk -v n="$name" '$0 == "CASE: " n { f = 1; next } /^CASE: / { f = 0 } f && /^MESSAGE: / { sub(/^MESSAGE: /, ""); print }' <<<"$out")
  if [ "$got" = "$want" ]; then
    printf 'ok    %-40s %-11s %s\n' "$name" "$got" "$msg"
  else
    printf 'FAIL  %-40s got %s, want %s: %s\n' "$name" "${got:-nothing}" "$want" "$msg"
    fail=1
  fi
done
exit "$fail"
