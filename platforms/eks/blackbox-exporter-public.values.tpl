# Platform eks, from value cluster (the bootstrap's, never in git): the DNS probes of the three public names. Each asks
# for an A record and fails on any answer without one (a tab separates the fields of a record).
{{- $c := .Values.cluster }}
{{- $names := dict "dns_web" $c.domain "dns_api" (printf "api.%s" $c.domain) "dns_media" $c.mediaDomain }}
config:
  modules:
    {{- range $module := keys $names | sortAlpha }}
    {{ $module }}:
      prober: dns
      timeout: 5s
      dns:
        query_name: {{ get $names $module | quote }}
        query_type: A
        preferred_ip_protocol: ip4
        valid_rcodes: [NOERROR]
        validate_answer_rrs:
          fail_if_none_matches_regexp: ['\tIN\tA\t']
    {{- end }}
