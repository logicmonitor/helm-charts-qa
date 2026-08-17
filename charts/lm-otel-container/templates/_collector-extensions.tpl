{{/*
Collector extension definitions (health_check, zpages ops/diagnostics) for agent/cluster config.yaml.
*/}}
{{- define "lm-otel-container.collectorExtensions" -}}
health_check:
  endpoint: 0.0.0.0:{{ .Values.collectorHealth.port }}
{{- if .Values.collectorManagement.enabled }}
zpages:
  endpoint: 0.0.0.0:{{ .Values.collectorManagement.port }}
{{- end }}
{{- end }}

{{/*
service.extensions entries shared by agent and cluster collectors.
Caller may append additional extensions (e.g. file_storage on the agent).
*/}}
{{- define "lm-otel-container.collectorServiceExtensions" -}}
- health_check
{{- if .Values.collectorManagement.enabled }}
- zpages
{{- end }}
{{- end }}

{{/*
Container ports for health, internal metrics telemetry, and management extension.
*/}}
{{- define "lm-otel-container.collectorContainerPorts" -}}
- name: health
  containerPort: {{ .Values.collectorHealth.port }}
  protocol: TCP
{{- if .Values.collectorMetrics.enabled }}
- name: metrics
  containerPort: {{ .Values.collectorMetrics.port }}
  protocol: TCP
{{- end }}
{{- if .Values.collectorManagement.enabled }}
- name: zpages
  containerPort: {{ .Values.collectorManagement.port }}
  protocol: TCP
{{- end }}
{{- end }}

{{/*
Cluster collector OTLP ports for trace ingest from application workloads.
*/}}
{{- define "lm-otel-container.traceContainerPorts" -}}
{{- if and .Values.traces.enabled .Values.traces.otlpGrpc.enabled }}
- name: otlp-grpc
  containerPort: {{ .Values.traces.otlpGrpc.port }}
  protocol: TCP
{{- end }}
{{- if and .Values.traces.enabled .Values.traces.otlpHttp.enabled }}
- name: otlp-http
  containerPort: {{ .Values.traces.otlpHttp.port }}
  protocol: TCP
{{- end }}
{{- end }}

{{/*
Cluster Service ports for health, metrics, and management.
*/}}
{{- define "lm-otel-container.collectorServicePorts" -}}
- name: health
  port: {{ .Values.collectorHealth.port }}
  targetPort: health
  protocol: TCP
{{- if .Values.collectorMetrics.enabled }}
- name: metrics
  port: {{ .Values.collectorMetrics.port }}
  targetPort: metrics
  protocol: TCP
{{- end }}
{{- if .Values.collectorManagement.enabled }}
- name: zpages
  port: {{ .Values.collectorManagement.port }}
  targetPort: zpages
  protocol: TCP
{{- end }}
{{- if and .Values.traces.enabled .Values.traces.otlpGrpc.enabled }}
- name: otlp-grpc
  port: {{ .Values.traces.otlpGrpc.port }}
  targetPort: otlp-grpc
  protocol: TCP
{{- end }}
{{- if and .Values.traces.enabled .Values.traces.otlpHttp.enabled }}
- name: otlp-http
  port: {{ .Values.traces.otlpHttp.port }}
  targetPort: otlp-http
  protocol: TCP
{{- end }}
{{- end }}
