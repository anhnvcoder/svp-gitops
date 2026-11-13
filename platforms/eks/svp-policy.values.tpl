# Platform eks, from value cluster (the bootstrap's, never in git): every image a pod names is pulled from the account's
# private ECR registry. Release images run from their own repositories there, copied by CI with their signatures and
# attestations, which policy svp-images reads in place; third-party images come through ECR's pull-through cache.
{{- $ecr := .Values.cluster.ecrRegistry }}
registryMirror:
  rules:
    - {from: ghcr.io/anhnvcoder/, to: {{ printf "%s/" $ecr | quote }}}
    - {from: ghcr.io/, to: {{ printf "%s/ghcr/" $ecr | quote }}}
    - {from: docker.io/, to: {{ printf "%s/docker-hub/" $ecr | quote }}}
    - {from: quay.io/, to: {{ printf "%s/quay/" $ecr | quote }}}
    - {from: registry.k8s.io/, to: {{ printf "%s/k8s/" $ecr | quote }}}
    - {from: public.ecr.aws/, to: {{ printf "%s/ecr-public/" $ecr | quote }}}
releaseRegistry: {{ $ecr | quote }}
# Kyverno logs in to ECR with its admission controller's EKS Pod Identity.
registryCredentials:
  providers: [amazon]
