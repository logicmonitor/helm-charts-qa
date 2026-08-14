{{/*
prometheus/ksm receiver block (kube-state-metrics scrape job).
*/}}
{{- define "lm-otel-container.prometheusReceiverKsm" -}}
{{- $applyMetrics := eq (include "lm-otel-container.filtering.applyToMetrics" .) "true" }}
{{- $nsRelabel := and $applyMetrics (or (not (empty .Values.filtering.excludeNamespaces)) (not (empty .Values.filtering.includeNamespaces))) }}
{{- $metricRelabel := or (not (empty .Values.filtering.excludeMetrics)) (not (empty .Values.filtering.includeMetrics)) }}
{{- $ksmRelabel := or $nsRelabel $metricRelabel }}
prometheus/ksm:
  config:
    scrape_configs:
      - job_name: kube-state-metrics
        scrape_interval: {{ .Values.ksm.scrapeInterval }}
        static_configs:
          - targets:
              - {{ include "lm-otel-container.ksmScrapeTarget" . | quote }}
{{- if $ksmRelabel }}
        metric_relabel_configs:
{{- if $nsRelabel }}
{{- range .Values.filtering.excludeNamespaces }}
          - source_labels: [namespace]
            regex: {{ printf "^%s$" . | quote }}
            action: drop
{{- end }}
{{- if not (empty .Values.filtering.includeNamespaces) }}
          - source_labels: [namespace]
            regex: {{ printf "^(%s)$" (join "|" .Values.filtering.includeNamespaces) | quote }}
            action: keep
{{- end }}
{{- end }}
{{- if not (empty .Values.filtering.excludeMetrics) }}
{{- range .Values.filtering.excludeMetrics }}
          - source_labels: [__name__]
            regex: {{ . | quote }}
            action: drop
{{- end }}
{{- end }}
{{- if not (empty .Values.filtering.includeMetrics) }}
          - source_labels: [__name__]
            regex: {{ printf "^(%s)$" (join "|" .Values.filtering.includeMetrics) | quote }}
            action: keep
{{- end }}
{{- end }}
{{- end }}
