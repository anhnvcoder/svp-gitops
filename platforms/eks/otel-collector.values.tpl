# Platform eks, from value cluster (the bootstrap's, never in git): the consumer groups' lag from the brokers of Amazon
# MSK, and where deploy/observability/otelcol/k8s-eks.yaml sends (the AMP workspace, the log group, the region of those
# and of X-Ray). A list replaces the base's whole, so every variable of the base is named again; the CA file is empty,
# which leaves the system's roots.
extraEnvs:
  - name: GOMEMLIMIT
    value: 140MiB
  - name: SVP_KAFKA_OTELCOL_PASSWORD
    valueFrom:
      secretKeyRef: {name: otelcol-kafka, key: password}
  - name: SVP_OTELCOL_KAFKA_BROKERS
    value: {{ .Values.cluster.kafkaBrokers | quote }}
  - name: SVP_OTELCOL_KAFKA_CA_FILE
    value: ""
  - name: SVP_OTELCOL_REGION
    value: {{ .Values.cluster.region | quote }}
  - name: SVP_OTELCOL_AMP_ENDPOINT
    value: {{ .Values.cluster.ampEndpoint | quote }}
  - name: SVP_OTELCOL_LOG_GROUP
    value: {{ .Values.cluster.logGroup | quote }}
