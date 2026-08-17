{{/*
service.telemetry controls collector runtime logs and optional self-metrics.
*/}}
{{- define "lm-otel-container.collectorTelemetry" -}}
telemetry:
  logs:
    level: {{ .Values.otel.logLevel | default "INFO" | lower | quote }}
{{- if .Values.collectorMetrics.enabled }}
  metrics:
    level: {{ .Values.collectorMetrics.level }}
    readers:
      - pull:
          exporter:
            prometheus:
              host: 0.0.0.0
              port: {{ .Values.collectorMetrics.port }}
{{- end }}
{{- end }}
