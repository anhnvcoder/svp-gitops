#!/usr/bin/env bash
# cluster-contract-test.sh [CODE_REPO]: the test of the contract of value cluster in templates/applications.yaml for the
# keys of AWS's managed services. The root chart of this folder is rendered for stg on eks with the example cluster map
# of the code repository (CODE_REPO, default ../backend beside this repository): once as it is, then with each such key
# missing, of another type and of another form, each of which must fail naming the key. Needs helm and jq, no network.
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd -P)
chart=$repo/argocd/apps
code=${1:-$repo/../backend}
example=$code/deploy/ci/cluster-values.example.yaml
[ -f "$example" ] || { echo "no $example: pass the folder of a clone of the code repository" >&2; exit 1; }
for tool in helm jq; do
  command -v "$tool" >/dev/null || { echo "$tool is not installed" >&2; exit 1; }
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HELM_CACHE_HOME=$tmp/helm/cache HELM_CONFIG_HOME=$tmp/helm/config HELM_DATA_HOME=$tmp/helm/data

# to_json FILE: the YAML documents of FILE as a JSON array, read by Helm's own parser (no yq needed): a chart of one
# template that splits the file at its --- lines (Helm wants a map at the top of what it renders).
mkdir -p "$tmp/json/templates"
printf 'apiVersion: v2\nname: to-json\nversion: 0.1.0\n' >"$tmp/json/Chart.yaml"
cat >"$tmp/json/templates/out.yaml" <<'EOF'
{{- $docs := list }}
{{- range regexSplit "(?m)^---[^\n]*$" (.Files.Get "in.yaml") -1 }}
{{- with fromYaml . }}{{ if hasKey . "Error" }}{{ fail (get . "Error") }}{{ end }}{{ $docs = append $docs . }}{{ end }}
{{- end }}
{{- toJson (dict "docs" $docs) }}
EOF
to_json() {
  cp "$1" "$tmp/json/in.yaml"
  helm template to-json "$tmp/json" | sed '/^---$/d; /^# Source:/d' | jq '.docs'
}

# The values level 1 of the root gives this chart for stg on eks: an image file for every release of chart
# svp-service, a commit and the two values derived from it (placeholders of their form), the example cluster map.
to_json "$example" | jq '.[0]' >"$tmp/cluster.json"
jq --slurpfile cluster "$tmp/cluster.json" '{
  env: "stg", platform: "eks", nodeArch: "arm64", cluster: $cluster[0],
  envFiles: {
    charts: {revision: ("0" * 40), podSecurityVersion: "v1.36", collectorConfigSha256: ("0" * 64)},
    overlays: {},
    images: ([.components[] | select(.path == "deploy/helm/svp-service") | {key: .name, value: {}}] | from_entries)
  }}' "$chart/components.json" >"$tmp/values.json"

fail=0
# render NAME FILTER: renders the chart with the values FILTER (jq) makes of the base values; output in $tmp/NAME.*.
render() {
  jq "$2" "$tmp/values.json" >"$tmp/$1.values.json"
  helm template svp-apps "$chart" -f "$tmp/$1.values.json" >"$tmp/$1.yaml" 2>"$tmp/$1.err"
}

# The example as it is renders, and the agent of kube-prometheus-stack writes to its workspace, in its region, as its
# cluster: the template of the platform reads those keys, and the platform's values file runs Prometheus as an agent.
if render example .; then
  to_json "$tmp/example.yaml" >"$tmp/example.json"
  got=$(jq -c '.[] | select(.kind == "Application" and .metadata.name == "kube-prometheus-stack") | .spec.sources[0].helm
    | [.valuesObject.prometheus.prometheusSpec | (.remoteWrite[0] | .url, .sigv4.region), .externalLabels.cluster]
      + [.valueFiles | index("$values/platforms/eks/kube-prometheus-stack.yaml") != null]' "$tmp/example.json")
  want=$(jq -c '[.ampEndpoint + "api/v1/remote_write", .region, .name, true]' "$tmp/cluster.json")
  agent=$(to_json "$repo/platforms/eks/kube-prometheus-stack.yaml" | jq -c '.[0].prometheus.agentMode')
  if [ "$got" = "$want" ] && [ "$agent" = true ]; then
    echo "ok    example renders; kube-prometheus-stack: remote write, region, cluster, values file $got, agentMode $agent"
  else
    echo "FAIL  example: kube-prometheus-stack has $got, want $want; agentMode of platforms/eks/ is $agent, want true"
    fail=1
  fi
else
  sed 's/^/    /' "$tmp/example.err"
  echo "FAIL  example: the example cluster map does not render"
  fail=1
fi

# Each key: missing, a number instead of a string, and a string of another form. The render must fail on that key.
keys="ecrRegistry ampWorkspaceId ampEndpoint logGroup grafanaUrl alarmTopicArn"
for key in $keys; do
  for broken in missing type form; do
    case $broken in
    missing) filter="del(.cluster.$key)" ;;
    type) filter=".cluster.$key = 123456789012" ;;
    # The example's value with an upper-case X after it: no form of the contract allows one at the end.
    form) filter=".cluster.$key += \"X\"" ;;
    esac
    name=$key-$broken
    if render "$name" "$filter"; then
      echo "FAIL  $name: renders, want the render to fail on cluster.$key"
      fail=1
    elif grep -q "cluster\.$key is " "$tmp/$name.err"; then
      echo "ok    $name: fails on cluster.$key"
    else
      sed 's/^/    /' "$tmp/$name.err"
      echo "FAIL  $name: fails, but not on cluster.$key (above)"
      fail=1
    fi
  done
done
exit "$fail"
