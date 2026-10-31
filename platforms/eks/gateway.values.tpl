# Platform eks, from value cluster (the bootstrap's, never in git).
env:
  # Playlist and thumbnail URLs handed to clients: the media bucket through its CloudFront distribution, whose paths
  # are the objects' keys (media/<id>/...), with no bucket name in front as on k3d's path-style store.
  MEDIA_PUBLIC_BASE_URL: {{ printf "https://%s" .Values.cluster.mediaDomain | quote }}
  # The pods' addresses are the VPC's (VPC CNI): Envoy's connections come from there. Still one trusted hop, Envoy's,
  # which sees the client's own address since the NLB keeps it; the policy of the release keeps every pod but Envoy's
  # and the web client's from reaching the gateway.
  TRUSTED_PROXY_CIDRS: {{ .Values.cluster.vpcCidr | quote }}
httpRoute:
  host: {{ printf "api.%s" .Values.cluster.domain | quote }}
