# Platform eks, from value cluster (the bootstrap's, never in git).
{{- $c := .Values.cluster }}
env:
  # S3's regional endpoint, for the service's own calls and for the upload form the browser posts to
  # (https://<uploads bucket>.s3.<region>.amazonaws.com, the web client's UPLOAD_ORIGIN).
  S3_ENDPOINT: {{ printf "https://s3.%s.amazonaws.com" $c.region | quote }}
  S3_PUBLIC_ENDPOINT: {{ printf "https://s3.%s.amazonaws.com" $c.region | quote }}
  S3_REGION: {{ $c.region | quote }}
  S3_UPLOADS_BUCKET: {{ $c.uploadsBucket | quote }}
  S3_MEDIA_BUCKET: {{ $c.mediaBucket | quote }}
# Egress by address instead of the in-cluster pods: RDS in the database subnets on 5432; S3's ranges of the region on
# 443, and the EKS Pod Identity agent on the node, where the pod gets its role's credentials.
externalPeers:
  postgres:
  {{- range $c.dbCidrs }}
    - {cidr: {{ . | quote }}, ports: [5432]}
  {{- end }}
  s3:
  {{- range $c.s3Cidrs }}
    - {cidr: {{ . | quote }}, ports: [443]}
  {{- end }}
    - {cidr: 169.254.170.23/32, ports: [80]}
