# Platform eks, from value cluster (the bootstrap's, never in git).
# The VPC's CIDR, where the nodes are: Prometheus scrapes each kubelet on 10250 there. Without it the kubelet targets
# are down and KubeletDown fires.
nodeSubnet: {{ .Values.cluster.vpcCidr | quote }}
postgres:
  external:
    # The database subnets: GlitchTip and its init Job reach RDS there on 5432.
    cidrs: {{ .Values.cluster.dbCidrs | toJson }}
