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
# The managed Grafana Grafana Operator writes the dashboards to, and the workspace its data source reads.
dashboards:
  grafana:
    url: {{ .Values.cluster.grafanaUrl | quote }}
    ampEndpoint: {{ .Values.cluster.ampEndpoint | quote }}
    region: {{ .Values.cluster.region | quote }}
# The VPC's CIDR, where the private DNS of the interface endpoints puts AMP, CloudWatch Logs and X-Ray.
awsEndpointCidrs:
  - {{ .Values.cluster.vpcCidr | quote }}
