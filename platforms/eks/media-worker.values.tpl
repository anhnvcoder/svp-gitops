# Platform eks, from value cluster (the bootstrap's, never in git).
{{- $c := .Values.cluster }}
env:
  S3_ENDPOINT: {{ printf "https://s3.%s.amazonaws.com" $c.region | quote }}
  S3_REGION: {{ $c.region | quote }}
  S3_UPLOADS_BUCKET: {{ $c.uploadsBucket | quote }}
  S3_MEDIA_BUCKET: {{ $c.mediaBucket | quote }}
# Egress by address instead of the in-cluster store: S3's ranges of the region on 443, and the EKS Pod Identity agent
# on the node, where the pod gets its role's credentials. Never 0.0.0.0/0: ffmpeg runs on uploaded files, and a worker
# taken over by one must reach no other host.
externalPeers:
  s3:
  {{- range $c.s3Cidrs }}
    - {cidr: {{ . | quote }}, ports: [443]}
  {{- end }}
    - {cidr: 169.254.170.23/32, ports: [80]}
