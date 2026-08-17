{{/*
Optional OpenTelemetry diagnostic exporters.
The debug exporter prints telemetry batches to stdout/stderr. The file exporter
writes log batches to a pod-local file without feeding collector stdout back into
filelog.
*/}}
{{- define "lm-otel-container.debugExporter" -}}
{{- if .Values.debugExporter.enabled }}
debug:
  verbosity: {{ .Values.debugExporter.verbosity }}
  sampling_initial: {{ .Values.debugExporter.samplingInitial }}
  sampling_thereafter: {{ .Values.debugExporter.samplingThereafter }}
  use_internal_logger: {{ .Values.debugExporter.useInternalLogger }}
{{- if not .Values.debugExporter.useInternalLogger }}
  output_paths:
{{- toYaml .Values.debugExporter.outputPaths | nindent 4 }}
{{- end }}
{{- end }}
{{- end }}

{{- define "lm-otel-container.diagnosticFileExporter" -}}
{{- if .Values.diagnosticFileExporter.enabled }}
file/diagnostics:
  path: {{ .Values.diagnosticFileExporter.path | quote }}
{{- end }}
{{- end }}

{{/*
Exporter lists for metrics and logs pipelines.
*/}}
{{- define "lm-otel-container.metricsExporters" -}}
- otlphttp
{{- if and .Values.debugExporter.enabled .Values.debugExporter.metrics.enabled }}
- debug
{{- end }}
{{- end }}

{{- define "lm-otel-container.logsExporters" -}}
- {{ include "lm-otel-container.logicmonitorSignalExporterName" . }}
{{- if and .Values.debugExporter.enabled .Values.debugExporter.logs.enabled }}
- debug
{{- end }}
{{- if .Values.diagnosticFileExporter.enabled }}
- file/diagnostics
{{- end }}
{{- end }}
