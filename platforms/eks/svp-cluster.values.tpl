# Platform eks, from value cluster (the bootstrap's, never in git): what of svp-cluster depends on the cluster.
{{- $c := .Values.cluster }}
{{- $net := splitList "." (first (splitList "/" $c.serviceCidr)) }}
# The VPC's CIDR: the control plane's network interfaces, where the API server and its webhook calls are.
nodeSubnet: {{ $c.vpcCidr | quote }}
# The VPC's CIDR again: the private DNS of the interface endpoints puts the AWS APIs Kyverno and External Secrets call
# (ECR, STS, Secrets Manager) there.
awsEndpointCidrs:
  - {{ $c.vpcCidr | quote }}
# Service kubernetes: the first address of the cluster's service range (a network address ending in .0, which the
# root chart checks).
kubeAPIServiceIP: {{ printf "%s.%s.%s.%d" (index $net 0) (index $net 1) (index $net 2) (add1 (atoi (index $net 3))) | quote }}
# Read only by a chart revision without listeners; with listeners below they name no listener.
wildcardHost: {{ printf "*.%s" $c.domain | quote }}
apexHost: {{ $c.domain | quote }}
# The ALB sends no SNI to its targets, so one listener with no hostname serves both names behind it: the web client at
# the domain itself and the API at api.<domain>. Routes attach to it by its name, https.
listeners:
  - name: https
    certificate: svp-edge
    secretName: svp-edge-tls
    dnsNames:
      - {{ $c.domain | quote }}
      - {{ printf "api.%s" $c.domain | quote }}
# EC2NodeClass default: node role <name>-karpenter-node and discovery tag karpenter.sh/discovery=<name> of the cluster.
karpenter:
  clusterName: {{ $c.name | quote }}
envoy:
  # The internal ALB's target group, made by Terraform; AWS Load Balancer Controller registers the Envoy pods in it.
  targetGroupArn: {{ $c.edgeTargetGroupArn | quote }}
  networkPolicy:
    # The ALB has addresses in the edge subnets alone, where no node or pod has one: from there only the ALB connects.
    # Namespace svp-load: the k6 Job that measures the cluster straight at Service svp-envoy, past CloudFront and WAF.
    httpsFrom:
    {{- range $c.edgeCidrs }}
      - ipBlock:
          cidr: {{ . | quote }}
    {{- end }}
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: svp-load
    healthCheck:
      from:
      {{- range $c.edgeCidrs }}
        - ipBlock:
            cidr: {{ . | quote }}
      {{- end }}
# The store of every namespace with ExternalSecrets (store aws, svp-cluster.yaml beside this file): entries
# svp/<env>/<entry> of Secrets Manager in the cluster's region, read through the IAM role of that namespace. A
# namespace without a role fails here, before Argo CD gets a store that cannot authenticate.
externalSecrets:
  prefix: {{ printf "svp/%s/" .Values.env | quote }}
  # Secret svp-obs/grafana-operator: the API token of Amazon Managed Grafana, which the session's bootstrap writes to
  # entry grafana-operator.
  grafanaOperator: true
  # The RDS instance's own address, the host of every connection string the ExternalSecrets build: sslmode=verify-full
  # checks the server's certificate against the host called, and RDS's certificate holds only that name.
  postgres: {{ printf "%s:5432" $c.rdsAddress | quote }}
  # The primary endpoint of ElastiCache, the host of the REDIS_URL the ExternalSecrets of svp build.
  valkey: {{ printf "%s:6379" $c.valkeyHost | quote }}
  aws:
    region: {{ $c.region | quote }}
    roles:
    {{- range $ns := list "svp" "svp-data" "svp-obs" "keda" "argocd" }}
      {{ $ns }}: {{ required (printf "cluster.externalSecretsRoles.%s: the IAM role of the SecretStore of namespace %s" $ns $ns) (get $c.externalSecretsRoles $ns) | quote }}
    {{- end }}
