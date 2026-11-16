# Platform eks, from value cluster (the bootstrap's, never in git).
# The VPC's CIDR, where the nodes are: Prometheus scrapes each kubelet on 10250 there. Without it the kubelet targets
# are down and KubeletDown fires.
nodeSubnet: {{ .Values.cluster.vpcCidr | quote }}
postgres:
  external:
    # The database subnets: GlitchTip and its init Job reach RDS there on 5432.
    cidrs: {{ .Values.cluster.dbCidrs | toJson }}
kafka:
  external:
    # The database subnets: the Collector reaches the MSK brokers there on 9096.
    cidrs: {{ .Values.cluster.dbCidrs | toJson }}
# The AMP workspace that evaluates the rules and the SNS topic its alert manager sends every alert to.
rules:
  amp:
    workspaceId: {{ .Values.cluster.ampWorkspaceId | quote }}
    alarmTopicArn: {{ .Values.cluster.alarmTopicArn | quote }}
    region: {{ .Values.cluster.region | quote }}
# The managed Grafana Grafana Operator writes the dashboards to, and the workspace its data source reads; none where
# the env has no Managed Grafana (grafanaUrl "").
dashboards:
  target: {{ ternary "none" "grafana-operator" (eq .Values.cluster.grafanaUrl "") | quote }}
  grafana:
    url: {{ .Values.cluster.grafanaUrl | quote }}
    ampEndpoint: {{ .Values.cluster.ampEndpoint | quote }}
    region: {{ .Values.cluster.region | quote }}
# The VPC's CIDR, where the private DNS of the interface endpoints puts AMP, CloudWatch Logs and X-Ray.
awsEndpointCidrs:
  - {{ .Values.cluster.vpcCidr | quote }}
# The uptime probes of the public names: web, api and the probe object of the media bucket through CloudFront, and
# their DNS names, asked of kube-dns (modules of platforms/eks/blackbox-exporter-public.values.tpl).
{{- $dns := "kube-dns.kube-system.svc.cluster.local:53" }}
probes:
  http:
    - {name: web, module: http_public, url: {{ printf "https://%s/healthz" .Values.cluster.domain | quote }}}
    - {name: api, module: http_public, url: {{ printf "https://api.%s/readyz" .Values.cluster.domain | quote }}}
    - {name: media, module: http_public, url: {{ printf "https://%s/media/uptime-probe.txt" .Values.cluster.mediaDomain | quote }}}
  dns:
    - {name: web, module: dns_web, server: {{ $dns | quote }}}
    - {name: api, module: dns_api, server: {{ $dns | quote }}}
    - {name: media, module: dns_media, server: {{ $dns | quote }}}
