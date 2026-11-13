# Platform eks, from value cluster (the bootstrap's, never in git): the workspace of Amazon Managed Service for
# Prometheus the agent writes to, signed with SigV4 by its EKS Pod Identity (ServiceAccount kps-prometheus).
{{- $c := .Values.cluster }}
prometheus:
  prometheusSpec:
    # The label the workspace deduplicates the two replicas by, the same on both.
    externalLabels:
      cluster: {{ $c.name | quote }}
    # Queue sizes of AWS's guide for remote write to the workspace; native histograms, which it stores.
    remoteWrite:
      - url: {{ printf "%sapi/v1/remote_write" $c.ampEndpoint | quote }}
        sigv4:
          region: {{ $c.region | quote }}
        sendNativeHistograms: true
        queueConfig:
          maxSamplesPerSend: 1000
          maxShards: 200
          capacity: 2500
