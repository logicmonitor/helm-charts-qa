{{/* vim: set filetype=mustache: */}}

{{- define "filter-config" -}}
{{- $disabledBatchingFilter := "contains(owner,\"Job\") && type == \"pod\"" }}
{{- $filterValues := append .Values.filters ($disabledBatchingFilter) }}
filters:
  {{ toYaml $filterValues | nindent 2 }}
{{- end -}}
