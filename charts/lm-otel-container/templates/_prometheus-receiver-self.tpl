{{/*
prometheus/self receiver — scrapes the collector's own telemetry endpoint.

Usage: include with dict "root" . "jobName" "otel-collector-agent"
*/}}
{{- define "lm-otel-container.prometheusReceiverSelf" -}}
{{- $root := .root -}}
{{- $jobName := .jobName -}}
prometheus/self:
  config:
    scrape_configs:
      - job_name: {{ $jobName | quote }}
        scrape_interval: {{ $root.Values.collectorMetrics.scrapeInterval }}
        static_configs:
          - targets:
              - {{ printf "127.0.0.1:%d" (int $root.Values.collectorMetrics.port) | quote }}
{{- end }}
