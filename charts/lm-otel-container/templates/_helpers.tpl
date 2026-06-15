{{/*
Expand the name of the chart.
*/}}
{{- define "lm-otel-container.name" -}}
lm-otel-container
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "lm-otel-container.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name (include "lm-otel-container.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Chart label
*/}}
{{- define "lm-otel-container.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "lm-otel-container.labels" -}}
helm.sh/chart: {{ include "lm-otel-container.chart" . }}
{{ include "lm-otel-container.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "lm-otel-container.selectorLabels" -}}
app.kubernetes.io/name: {{ include "lm-otel-container.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Collector component labels
*/}}
{{- define "lm-otel-container.agent.labels" -}}
{{ include "lm-otel-container.labels" . }}
app.kubernetes.io/component: otel-agent
{{- end }}

{{- define "lm-otel-container.cluster.labels" -}}
{{ include "lm-otel-container.labels" . }}
app.kubernetes.io/component: otel-cluster
{{- end }}

{{/*
ServiceAccount name
*/}}
{{- define "lm-otel-container.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "lm-otel-container.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Secret holding Bearer token (must exist before install)
*/}}
{{- define "lm-otel-container.secretName" -}}
{{- .Values.auth.existingSecret }}
{{- end }}

{{/*
LogicMonitor OTLP/HTTP metrics endpoint URL
*/}}
{{- define "lm-otel-container.metricsEndpoint" -}}
{{- $domain := .Values.portalDomain | default "logicmonitor.com" }}
{{- printf "https://%s.%s/rest/api/v1/metrics" .Values.portalName $domain }}
{{- end }}

{{/*
Bundled kube-state-metrics scrape target host:port (no scheme).
External ksm.url must be host:port as used by Prometheus static_configs.
*/}}
{{- define "lm-otel-container.ksmScrapeTarget" -}}
{{- if .Values.ksm.url }}
{{- .Values.ksm.url }}
{{- else }}
{{- printf "%s-kube-state-metrics:8080" .Release.Name }}
{{- end }}
{{- end }}

{{/*
Fail fast validation — invoked from templates/validate.yaml
*/}}
{{- define "lm-otel-container.validateRequiredValues" -}}
{{- if not .Values.portalName }}
{{- fail "lm-otel-container: portalName is required" }}
{{- end }}
{{- if not (and .Values.auth.existingSecret (ne .Values.auth.existingSecret "")) }}
{{- fail "lm-otel-container: auth.existingSecret is required (create a Secret with the bearer token before install)" }}
{{- end }}
{{- if eq .Values.clusterIdentity.mode "explicit" }}
{{- if not .Values.clusterName }}
{{- fail "lm-otel-container: clusterName is required when clusterIdentity.mode is explicit" }}
{{- end }}
{{- end }}
{{- if and .Values.ksm.url .Values.ksm.bundled.enabled }}
{{- fail "lm-otel-container: when ksm.url is set, set ksm.bundled.enabled to false (bundled kube-state-metrics is not installed with an external endpoint)" }}
{{- end }}
{{- if and .Values.clusterCollector.enabled (not .Values.ksm.url) (not .Values.ksm.bundled.enabled) }}
{{- fail "lm-otel-container: cluster collector requires kube-state-metrics — set ksm.url (external) or ksm.bundled.enabled true (bundled sub-chart)" }}
{{- end }}
{{- end }}

{{/*
OTTL helper: (ns == "a") or (ns == "b") for namespace allowlist membership
*/}}
{{- define "lm-otel-container.ottlNamespaceOrEquals" -}}
({{- range $i, $n := . }}{{ if $i }} or {{ end }}resource.attributes["k8s.namespace.name"] == {{ $n | quote }}{{ end }})
{{- end }}
