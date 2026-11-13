# Platform eks, from value cluster (the bootstrap's, never in git).
{{- $c := .Values.cluster }}
env:
  S3_ENDPOINT: {{ printf "https://s3.%s.amazonaws.com" $c.region | quote }}
  S3_REGION: {{ $c.region | quote }}
  S3_UPLOADS_BUCKET: {{ $c.uploadsBucket | quote }}
  S3_MEDIA_BUCKET: {{ $c.mediaBucket | quote }}
  KAFKA_BROKERS: {{ $c.kafkaBrokers | quote }}
  MEDIACONVERT_QUEUE_ARN: {{ $c.mediaconvertQueueArn | quote }}
  MEDIACONVERT_ROLE_ARN: {{ $c.mediaconvertRoleArn | quote }}
  TRANSCODE_EVENTS_QUEUE_URL: {{ $c.transcodeEventsQueueUrl | quote }}
# Egress by address: S3's ranges of the region and the VPC on 443 (the interface endpoints MediaConvert and SQS resolve
# to), the EKS Pod Identity agent on the node, MSK in the database subnets on 9096. Never 0.0.0.0/0: the pod's role
# creates jobs and writes the media bucket. The price: 443 to every address of the VPC, not only to the endpoints.
externalPeers:
  s3:
  {{- range $c.s3Cidrs }}
    - {cidr: {{ . | quote }}, ports: [443]}
  {{- end }}
    - {cidr: {{ $c.vpcCidr | quote }}, ports: [443]}
    - {cidr: 169.254.170.23/32, ports: [80]}
  kafka:
  {{- range $c.dbCidrs }}
    - {cidr: {{ . | quote }}, ports: [9096]}
  {{- end }}
