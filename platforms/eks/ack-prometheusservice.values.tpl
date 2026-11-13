# Platform eks, from value cluster (the bootstrap's, never in git): the region of the AMP workspace the controller
# calls, told rather than read from the instance metadata, which pods cannot reach (IMDSv2, hop limit 1).
aws:
  region: {{ .Values.cluster.region | quote }}
