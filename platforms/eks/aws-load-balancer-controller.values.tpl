# Platform eks, from value cluster (the bootstrap's, never in git): the controller's cluster, told rather than read from
# the instance metadata, which pods cannot reach (IMDSv2, hop limit 1).
clusterName: {{ .Values.cluster.name | quote }}
region: {{ .Values.cluster.region | quote }}
vpcId: {{ .Values.cluster.vpcId | quote }}
