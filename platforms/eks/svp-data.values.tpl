# Platform eks, from value cluster (the bootstrap's, never in git): the RDS instance, the MSK brokers and the
# ElastiCache primary endpoint of the cluster.
postgres:
  external:
    host: {{ .Values.cluster.rdsAddress | quote }}
    # The database subnets: the only addresses the pg-bootstrap Job and svp-ops reach on 5432.
    cidrs: {{ .Values.cluster.dbCidrs | toJson }}
kafka:
  brokers: {{ .Values.cluster.kafkaBrokers | quote }}
  external:
    # The database subnets, where the brokers are: the only addresses Job kafka-init and svp-ops reach on 9096.
    cidrs: {{ .Values.cluster.dbCidrs | toJson }}
valkey:
  # svp-ops's valkey-cli logs in there.
  host: {{ .Values.cluster.valkeyHost | quote }}
  external:
    # The database subnets: the only addresses svp-ops reaches on 6379.
    cidrs: {{ .Values.cluster.dbCidrs | toJson }}
