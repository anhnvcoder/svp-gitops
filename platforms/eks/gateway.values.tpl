# Platform eks, from value cluster (the bootstrap's, never in git).
env:
  # Playlist and thumbnail URLs handed to clients: the media bucket through its CloudFront distribution, whose paths
  # are the objects' keys (media/<id>/...), with no bucket name in front as on k3d's path-style store.
  MEDIA_PUBLIC_BASE_URL: {{ printf "https://%s" .Values.cluster.mediaDomain | quote }}
  # The client's address is the one CloudFront writes into CloudFront-Viewer-Address, replacing any the viewer sent;
  # X-Forwarded-For is not read. Believed only on connections from the pods of the VPC (VPC CNI), which the policy of
  # the release narrows to Envoy's and the web client's; Envoy is reached only by the ALB and the in-cluster load test.
  TRUSTED_CLIENT_ADDRESS_HEADER: CloudFront-Viewer-Address
  TRUSTED_PROXY_HOPS: "0"
  TRUSTED_PROXY_CIDRS: {{ .Values.cluster.vpcCidr | quote }}
httpRoute:
  host: {{ printf "api.%s" .Values.cluster.domain | quote }}
# Valkey is ElastiCache, reached by address in the database subnets on 6379 instead of the in-cluster pod.
externalPeers:
  valkey:
  {{- range .Values.cluster.dbCidrs }}
    - {cidr: {{ . | quote }}, ports: [6379]}
  {{- end }}
# The canary's analysis asks the env's AMP workspace (no Prometheus answers queries in the cluster: the agent only
# writes), signed with SigV4 by Argo Rollouts' EKS Pod Identity.
canaryPrometheus:
  address: {{ trimSuffix "/" .Values.cluster.ampEndpoint | quote }}
  sigv4Region: {{ .Values.cluster.region | quote }}
