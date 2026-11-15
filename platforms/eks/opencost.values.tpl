# Platform eks, from value cluster (the bootstrap's, never in git): the workspace OpenCost queries, the region and host
# its SigV4 proxy signs for, and the cluster's name as OpenCost's cluster id.
{{- $c := .Values.cluster }}
opencost:
  exporter:
    defaultClusterId: {{ $c.name | quote }}
  prometheus:
    amp:
      workspaceId: {{ $c.ampWorkspaceId | quote }}
  sigV4Proxy:
    region: {{ $c.region | quote }}
    host: {{ printf "aps-workspaces.%s.amazonaws.com" $c.region | quote }}
