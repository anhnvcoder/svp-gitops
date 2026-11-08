# Platform eks, from value cluster (the bootstrap's, never in git): Postgres is RDS, Kafka MSK and Valkey ElastiCache,
# reached by address in the database subnets on 5432, 9096 and 6379 instead of the in-cluster pods.
env:
  KAFKA_BROKERS: {{ .Values.cluster.kafkaBrokers | quote }}
externalPeers:
  postgres:
  {{- range .Values.cluster.dbCidrs }}
    - {cidr: {{ . | quote }}, ports: [5432]}
  {{- end }}
  kafka:
  {{- range .Values.cluster.dbCidrs }}
    - {cidr: {{ . | quote }}, ports: [9096]}
  {{- end }}
  valkey:
  {{- range .Values.cluster.dbCidrs }}
    - {cidr: {{ . | quote }}, ports: [6379]}
  {{- end }}
