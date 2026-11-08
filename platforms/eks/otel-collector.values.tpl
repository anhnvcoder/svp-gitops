# Platform eks, from value cluster (the bootstrap's, never in git): the consumer groups' lag from the brokers of Amazon
# MSK. A list replaces the base's whole, so every variable of the base is named again; the CA file is empty, which
# leaves the system's roots.
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
