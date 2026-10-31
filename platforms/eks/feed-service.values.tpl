# Platform eks, from value cluster (the bootstrap's, never in git): Postgres is RDS, reached by address in the
# database subnets on 5432 instead of the in-cluster pods.
externalPeers:
  postgres:
  {{- range .Values.cluster.dbCidrs }}
    - {cidr: {{ . | quote }}, ports: [5432]}
  {{- end }}
