{{/* vim: set filetype=mustache: */}}

{{- define "collector-config" -}}
replicas: {{ .Values.collector.replicas }}
size: {{ .Values.collector.size | quote}}
{{- if .Values.collector.useEA }}
useEA: {{ .Values.collector.useEA }}
{{- else }}
useEA: false
{{- end }}
{{- if .Values.collector.lm.escalationChainID }}
lm:
  escalationChainID: {{ .Values.collector.lm.escalationChainID }}
{{- else }}
lm:
  escalationChainID: 0
{{- end }}
{{- end -}}
