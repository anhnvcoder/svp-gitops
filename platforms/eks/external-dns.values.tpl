# Platform eks, from value cluster (the bootstrap's, never in git).
# Owner of every record it makes (the TXT record beside each): the cluster's name, so a second cluster writing to the
# same zone never deletes this one's records, nor this one theirs.
txtOwnerId: {{ .Values.cluster.name | quote }}
# Names under the cluster's domain only (the web client's, api.<domain>).
domainFilters: {{ list .Values.cluster.domain | toJson }}
extraArgs:
  # The lab's hosted zone and no other, whatever else the account holds.
  zone-id-filter: {{ list .Values.cluster.hostedZoneId | toJson }}
env:
  # The region of the AWS API calls; pods cannot read it from the instance metadata (IMDSv2, hop limit 1).
  - name: AWS_DEFAULT_REGION
    value: {{ .Values.cluster.region | quote }}
