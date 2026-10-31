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
