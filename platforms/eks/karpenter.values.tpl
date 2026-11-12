# Platform eks, from value cluster (the bootstrap's, never in git): the cluster Karpenter launches nodes for and its
# interruption queue, whose name Terraform derives from the cluster's (<name>-karpenter).
settings:
  clusterName: {{ .Values.cluster.name | quote }}
  interruptionQueue: {{ printf "%s-karpenter" .Values.cluster.name | quote }}
controller:
  # The region of the AWS API calls; without it the controller asks the instance metadata, which pods cannot reach
  # (IMDSv2, hop limit 1).
  env:
    - name: AWS_REGION
      value: {{ .Values.cluster.region | quote }}
