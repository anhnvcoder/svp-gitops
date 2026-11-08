# Platform eks, from value cluster (the bootstrap's, never in git): what of svp-cluster depends on the cluster.
{{- $c := .Values.cluster }}
{{- $net := splitList "." (first (splitList "/" $c.serviceCidr)) }}
# The VPC's CIDR: the control plane's network interfaces, where the API server and its webhook calls are.
nodeSubnet: {{ $c.vpcCidr | quote }}
# Service kubernetes: the first address of the cluster's service range (a network address ending in .0, which the
# root chart checks).
kubeAPIServiceIP: {{ printf "%s.%s.%s.%d" (index $net 0) (index $net 1) (index $net 2) (add1 (atoi (index $net 3))) | quote }}
# The web client at the domain itself (listener https-apex), the API and anything else below it (listener https).
wildcardHost: {{ printf "*.%s" $c.domain | quote }}
apexHost: {{ $c.domain | quote }}
tls:
  acme:
    email: {{ $c.acmeEmail | quote }}
    hostedZoneId: {{ $c.hostedZoneId | quote }}
    region: {{ $c.region | quote }}
envoy:
  networkPolicy:
    # The NLB's health checks come from its nodes' addresses in the VPC.
    healthCheckCIDR: {{ $c.vpcCidr | quote }}
# The store of every namespace with ExternalSecrets (store aws, svp-cluster.yaml beside this file): entries
# svp/<env>/<entry> of Secrets Manager in the cluster's region, read through the IAM role of that namespace. A
# namespace without a role fails here, before Argo CD gets a store that cannot authenticate.
externalSecrets:
  prefix: {{ printf "svp/%s/" .Values.env | quote }}
  # The primary endpoint of ElastiCache, the host of the REDIS_URL the ExternalSecrets of svp build.
  valkey: {{ printf "%s:6379" $c.valkeyHost | quote }}
  aws:
    region: {{ $c.region | quote }}
    roles:
    {{- range $ns := list "svp" "svp-data" "svp-obs" "keda" "argocd" }}
      {{ $ns }}: {{ required (printf "cluster.externalSecretsRoles.%s: the IAM role of the SecretStore of namespace %s" $ns $ns) (get $c.externalSecretsRoles $ns) | quote }}
    {{- end }}
