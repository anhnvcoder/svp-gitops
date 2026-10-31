# Platform eks, from value cluster (the bootstrap's, never in git): the RDS instance of the cluster.
postgres:
  external:
    host: {{ .Values.cluster.rdsAddress | quote }}
    # The database subnets: the only addresses the pg-bootstrap Job reaches on 5432.
    cidrs: {{ .Values.cluster.dbCidrs | toJson }}
