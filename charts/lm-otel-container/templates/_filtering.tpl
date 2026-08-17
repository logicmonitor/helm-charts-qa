{{/*
Signal filtering helpers: OTTL conditions and filter/main processor rendering.
Namespace and workload filters can apply to metrics, logs, and traces via
filtering.applyTo. Metric-name filters apply to metrics only.
*/}}

{{- define "lm-otel-container.filtering.applyToMetrics" -}}
{{- $applyTo := .Values.filtering.applyTo | default dict -}}
{{- if hasKey $applyTo "metrics" }}{{ $applyTo.metrics }}{{ else }}true{{ end -}}
{{- end }}

{{- define "lm-otel-container.filtering.applyToLogs" -}}
{{- $applyTo := .Values.filtering.applyTo | default dict -}}
{{- if hasKey $applyTo "logs" }}{{ $applyTo.logs }}{{ else }}true{{ end -}}
{{- end }}

{{- define "lm-otel-container.filtering.applyToTraces" -}}
{{- $applyTo := .Values.filtering.applyTo | default dict -}}
{{- if hasKey $applyTo "traces" }}{{ $applyTo.traces }}{{ else }}true{{ end -}}
{{- end }}

{{- define "lm-otel-container.filtering.hasNamespaceFilters" -}}
{{- or (not (empty .Values.filtering.excludeNamespaces)) (not (empty .Values.filtering.includeNamespaces)) -}}
{{- end }}

{{- define "lm-otel-container.filtering.hasWorkloadFilters" -}}
{{- or
  (not (empty .Values.filtering.excludeDeployments)) (not (empty .Values.filtering.includeDeployments))
  (not (empty .Values.filtering.excludeStatefulSets)) (not (empty .Values.filtering.includeStatefulSets))
  (not (empty .Values.filtering.excludeDaemonSets)) (not (empty .Values.filtering.includeDaemonSets))
  (not (empty .Values.filtering.excludeJobs)) (not (empty .Values.filtering.includeJobs))
  (not (empty .Values.filtering.excludeCronJobs)) (not (empty .Values.filtering.includeCronJobs))
-}}
{{- end }}

{{- define "lm-otel-container.filtering.hasMetricNameFilters" -}}
{{- or (not (empty .Values.filtering.excludeMetrics)) (not (empty .Values.filtering.includeMetrics)) -}}
{{- end }}

{{- define "lm-otel-container.filtering.hasResourceAttrFilters" -}}
{{- or (eq (include "lm-otel-container.filtering.hasNamespaceFilters" .) "true") (eq (include "lm-otel-container.filtering.hasWorkloadFilters" .) "true") -}}
{{- end }}

{{- define "lm-otel-container.filtering.hasMetricsFilter" -}}
{{- and (eq (include "lm-otel-container.filtering.applyToMetrics" .) "true") (or (eq (include "lm-otel-container.filtering.hasResourceAttrFilters" .) "true") (eq (include "lm-otel-container.filtering.hasMetricNameFilters" .) "true")) -}}
{{- end }}

{{- define "lm-otel-container.filtering.hasLogsFilter" -}}
{{- and (eq (include "lm-otel-container.filtering.applyToLogs" .) "true") (eq (include "lm-otel-container.filtering.hasResourceAttrFilters" .) "true") -}}
{{- end }}

{{- define "lm-otel-container.filtering.hasTracesFilter" -}}
{{- and (eq (include "lm-otel-container.filtering.applyToTraces" .) "true") (eq (include "lm-otel-container.filtering.hasResourceAttrFilters" .) "true") -}}
{{- end }}

{{- define "lm-otel-container.filtering.hasAnyFilter" -}}
{{- or (eq (include "lm-otel-container.filtering.hasMetricsFilter" .) "true") (eq (include "lm-otel-container.filtering.hasLogsFilter" .) "true") (eq (include "lm-otel-container.filtering.hasTracesFilter" .) "true") -}}
{{- end }}

{{/*
Fail when include and exclude are both set for the same namespace/workload dimension.
*/}}
{{- define "lm-otel-container.filtering.validate" -}}
{{- if and (not (empty .Values.filtering.includeNamespaces)) (not (empty .Values.filtering.excludeNamespaces)) }}
{{- fail "lm-otel-container: set filtering.includeNamespaces or filtering.excludeNamespaces, not both" }}
{{- end }}
{{- if and (not (empty .Values.filtering.includeDeployments)) (not (empty .Values.filtering.excludeDeployments)) }}
{{- fail "lm-otel-container: set filtering.includeDeployments or filtering.excludeDeployments, not both" }}
{{- end }}
{{- if and (not (empty .Values.filtering.includeStatefulSets)) (not (empty .Values.filtering.excludeStatefulSets)) }}
{{- fail "lm-otel-container: set filtering.includeStatefulSets or filtering.excludeStatefulSets, not both" }}
{{- end }}
{{- if and (not (empty .Values.filtering.includeDaemonSets)) (not (empty .Values.filtering.excludeDaemonSets)) }}
{{- fail "lm-otel-container: set filtering.includeDaemonSets or filtering.excludeDaemonSets, not both" }}
{{- end }}
{{- if and (not (empty .Values.filtering.includeJobs)) (not (empty .Values.filtering.excludeJobs)) }}
{{- fail "lm-otel-container: set filtering.includeJobs or filtering.excludeJobs, not both" }}
{{- end }}
{{- if and (not (empty .Values.filtering.includeCronJobs)) (not (empty .Values.filtering.excludeCronJobs)) }}
{{- fail "lm-otel-container: set filtering.includeCronJobs or filtering.excludeCronJobs, not both" }}
{{- end }}
{{- end }}

{{/*
OTTL OR-equals for an arbitrary resource attribute.
Usage: include with dict "attr" "k8s.deployment.name" "values" $list
*/}}
{{- define "lm-otel-container.ottlAttrOrEquals" -}}
({{- range $i, $n := .values }}{{ if $i }} or {{ end }}resource.attributes[{{ $.attr | quote }}] == {{ $n | quote }}{{ end }})
{{- end }}

{{/*
Render OTTL drop conditions for namespace + workload resource attributes.
Output is indented list items under a filterprocessor signal context.
*/}}
{{- define "lm-otel-container.filtering.resourceAttrConditions" -}}
{{- range .Values.filtering.excludeNamespaces }}
            - 'resource.attributes["k8s.namespace.name"] == {{ . | quote }}'
{{- end }}
{{- if not (empty .Values.filtering.includeNamespaces) }}
            - 'resource.attributes["k8s.namespace.name"] != nil and not ({{ include "lm-otel-container.ottlNamespaceOrEquals" .Values.filtering.includeNamespaces }})'
{{- end }}
{{- range .Values.filtering.excludeDeployments }}
            - 'resource.attributes["k8s.deployment.name"] == {{ . | quote }}'
{{- end }}
{{- if not (empty .Values.filtering.includeDeployments) }}
            - 'resource.attributes["k8s.deployment.name"] != nil and not ({{ include "lm-otel-container.ottlAttrOrEquals" (dict "attr" "k8s.deployment.name" "values" .Values.filtering.includeDeployments) }})'
{{- end }}
{{- range .Values.filtering.excludeStatefulSets }}
            - 'resource.attributes["k8s.statefulset.name"] == {{ . | quote }}'
{{- end }}
{{- if not (empty .Values.filtering.includeStatefulSets) }}
            - 'resource.attributes["k8s.statefulset.name"] != nil and not ({{ include "lm-otel-container.ottlAttrOrEquals" (dict "attr" "k8s.statefulset.name" "values" .Values.filtering.includeStatefulSets) }})'
{{- end }}
{{- range .Values.filtering.excludeDaemonSets }}
            - 'resource.attributes["k8s.daemonset.name"] == {{ . | quote }}'
{{- end }}
{{- if not (empty .Values.filtering.includeDaemonSets) }}
            - 'resource.attributes["k8s.daemonset.name"] != nil and not ({{ include "lm-otel-container.ottlAttrOrEquals" (dict "attr" "k8s.daemonset.name" "values" .Values.filtering.includeDaemonSets) }})'
{{- end }}
{{- range .Values.filtering.excludeJobs }}
            - 'resource.attributes["k8s.job.name"] == {{ . | quote }}'
{{- end }}
{{- if not (empty .Values.filtering.includeJobs) }}
            - 'resource.attributes["k8s.job.name"] != nil and not ({{ include "lm-otel-container.ottlAttrOrEquals" (dict "attr" "k8s.job.name" "values" .Values.filtering.includeJobs) }})'
{{- end }}
{{- range .Values.filtering.excludeCronJobs }}
            - 'resource.attributes["k8s.cronjob.name"] == {{ . | quote }}'
{{- end }}
{{- if not (empty .Values.filtering.includeCronJobs) }}
            - 'resource.attributes["k8s.cronjob.name"] != nil and not ({{ include "lm-otel-container.ottlAttrOrEquals" (dict "attr" "k8s.cronjob.name" "values" .Values.filtering.includeCronJobs) }})'
{{- end }}
{{- end }}

{{/*
Metric-name OTTL conditions (metrics.datapoint context only).
*/}}
{{- define "lm-otel-container.filtering.metricNameConditions" -}}
{{- range .Values.filtering.excludeMetrics }}
            - 'IsMatch(metric.name, {{ . | quote }})'
{{- end }}
{{- if not (empty .Values.filtering.includeMetrics) }}
            - 'not IsMatch(metric.name, {{ printf "^(%s)$" (join "|" .Values.filtering.includeMetrics) | quote }})'
{{- end }}
{{- end }}

{{/*
Render filter/main with metrics/logs/traces sections as needed.
*/}}
{{- define "lm-otel-container.filtering.filterMainProcessor" -}}
{{- if eq (include "lm-otel-container.filtering.hasAnyFilter" .) "true" }}
      filter/main:
        error_mode: ignore
{{- if eq (include "lm-otel-container.filtering.hasMetricsFilter" .) "true" }}
        metrics:
          datapoint:
{{- include "lm-otel-container.filtering.resourceAttrConditions" . }}
{{- include "lm-otel-container.filtering.metricNameConditions" . }}
{{- end }}
{{- if eq (include "lm-otel-container.filtering.hasLogsFilter" .) "true" }}
        logs:
          log_record:
{{- include "lm-otel-container.filtering.resourceAttrConditions" . }}
{{- end }}
{{- if eq (include "lm-otel-container.filtering.hasTracesFilter" .) "true" }}
        traces:
          span:
{{- include "lm-otel-container.filtering.resourceAttrConditions" . }}
{{- end }}
{{- end }}
{{- end }}
