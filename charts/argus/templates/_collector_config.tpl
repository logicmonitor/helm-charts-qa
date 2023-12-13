{{/* vim: set filetype=mustache: */}}

{{- define "collector-config" -}}
replicas: {{ .Values.collector.replicas }}
size: {{ .Values.collector.size | quote}}
useEA: {{ .Values.collector.useEA }}
lm:
  escalationChainID: {{ .Values.collector.lm.escalationChainID }}
{{- end -}}
