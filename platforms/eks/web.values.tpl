# Platform eks, from value cluster (the bootstrap's, never in git): the origins the browser uses.
env:
  APP_ORIGIN: {{ printf "https://%s" .Values.cluster.domain | quote }}
  # HLS and thumbnails: the media bucket's CloudFront distribution, the origin of the gateway's MEDIA_PUBLIC_BASE_URL.
  MEDIA_ORIGIN: {{ printf "https://%s" .Values.cluster.mediaDomain | quote }}
  # The presigned upload form posts straight to the uploads bucket, virtual-hosted (the bucket in the host name), the
  # URL video-service's form names; the Content-Security-Policy allows exactly this origin.
  UPLOAD_ORIGIN: {{ printf "https://%s.s3.%s.amazonaws.com" .Values.cluster.uploadsBucket .Values.cluster.region | quote }}
httpRoute:
  host: {{ .Values.cluster.domain | quote }}
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
