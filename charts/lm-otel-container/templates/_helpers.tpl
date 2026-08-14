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
{{- else if and .Values.clusterName (eq .Values.clusterIdentity.mode "explicit") }}
{{- .Values.clusterName | trunc 63 | trimSuffix "-" }}
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
Secret holding Bearer token (created by chart or existing)
*/}}
{{- define "lm-otel-container.secretName" -}}
{{- if .Values.auth.existingSecret }}
{{- .Values.auth.existingSecret }}
{{- else }}
{{- printf "%s-auth" (include "lm-otel-container.fullname" .) }}
{{- end }}
{{- end }}

{{/*
LogicMonitor OTLP/HTTP metrics endpoint URL (uses portalName and portalDomain).
Kept for internal use by partial templates; new config blocks use
${env:LOGICMONITOR_ACCOUNT} and ${env:LOGICMONITOR_DOMAIN} directly.
*/}}
{{- define "lm-otel-container.metricsEndpoint" -}}
{{- printf "https://%s.%s/rest/api/v1/metrics" .Values.portalName (.Values.portalDomain | default "logicmonitor.com") }}
{{- end }}

{{/*
Bundled kube-state-metrics scrape target host:port (no scheme).
External ksm.url must be host:port as used by Prometheus static_configs.
*/}}
{{- define "lm-otel-container.ksmScrapeTarget" -}}
{{- if .Values.ksm.url }}
{{- .Values.ksm.url }}
{{- else }}
{{- printf "%s:8080" (include "lm-otel-container.ksmFullname" .) }}
{{- end }}
{{- end }}

{{/*
Bundled kube-state-metrics resource name.
Defaults to "{fullname}-ksm" when kube-state-metrics.fullnameOverride is unset.
*/}}
{{- define "lm-otel-container.ksmFullname" -}}
{{- $ksm := index .Values "kube-state-metrics" | default dict }}
{{- if $ksm.fullnameOverride }}
{{- $ksm.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else if $ksm.nameOverride }}
{{- printf "%s-%s" .Release.Name ($ksm.nameOverride | trunc 63 | trimSuffix "-") | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-kube-state-metrics" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
LM collector registration env for the cluster collector (lm-otel type only).
Cluster collector is StatefulSet-only, so registration uses the stable pod ordinal.
*/}}
{{- define "lm-otel-container.clusterOtelNameEnv" -}}
{{- if eq .Values.collector.type "lm-otel" }}
- name: LOGICMONITOR_OTEL_NAME
  value: "$(CLUSTER_NAME)_cluster_$(MY_POD_ORDINAL)"
{{- end }}
{{- end }}

{{/*
Fail fast validation - invoked from templates/validate.yaml
*/}}
{{- define "lm-otel-container.validateRequiredValues" -}}
{{- if not .Values.portalName }}
{{- fail "lm-otel-container: portalName is required" }}
{{- end }}
{{- $hasToken := and .Values.auth.bearerToken (ne .Values.auth.bearerToken "") }}
{{- $hasExisting := and .Values.auth.existingSecret (ne .Values.auth.existingSecret "") }}
{{- if and $hasToken $hasExisting }}
{{- fail "lm-otel-container: set either auth.bearerToken or auth.existingSecret, not both" }}
{{- end }}
{{- if not (or $hasToken $hasExisting) }}
{{- fail "lm-otel-container: provide auth.bearerToken or auth.existingSecret" }}
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
{{- fail "lm-otel-container: cluster collector requires kube-state-metrics - set ksm.url (external) or ksm.bundled.enabled true (bundled sub-chart)" }}
{{- end }}
{{- if and (hasKey .Values.clusterCollector "kind") (ne (.Values.clusterCollector.kind | default "StatefulSet") "StatefulSet") }}
{{- fail "lm-otel-container: clusterCollector.kind=Deployment is no longer supported; the cluster collector is StatefulSet-only" }}
{{- end }}
{{- if and .Values.controlPlaneMonitoring.enabled (not .Values.clusterCollector.enabled) }}
{{- fail "lm-otel-container: controlPlaneMonitoring requires clusterCollector.enabled true" }}
{{- end }}
{{- $supportedSignalCollector := or (eq .Values.collector.type "lm-otel") (eq .Values.collector.type "otel-collector-contrib") }}
{{- if not $supportedSignalCollector }}
{{- fail "lm-otel-container: collector.type must be lm-otel or otel-collector-contrib" }}
{{- end }}
{{- if and (or .Values.logs.enabled .Values.events.enabled .Values.traces.enabled) (not $supportedSignalCollector) }}
{{- fail "lm-otel-container: logs.enabled, events.enabled, and traces.enabled require collector.type: lm-otel or otel-collector-contrib" }}
{{- end }}
{{- if and .Values.traces.enabled (not .Values.clusterCollector.enabled) }}
{{- fail "lm-otel-container: traces.enabled requires clusterCollector.enabled true" }}
{{- end }}
{{- if and .Values.traces.enabled (not (or .Values.traces.otlpGrpc.enabled .Values.traces.otlpHttp.enabled)) }}
{{- fail "lm-otel-container: traces.enabled requires traces.otlpGrpc.enabled or traces.otlpHttp.enabled" }}
{{- end }}
{{- if and .Values.traces.enabled .Values.traces.tailSampling.enabled (empty .Values.traces.tailSampling.policies) }}
{{- fail "lm-otel-container: traces.tailSampling.enabled requires at least one traces.tailSampling.policies item" }}
{{- end }}
{{- if .Values.debugExporter.enabled }}
{{- $debugLogsPipeline := and .Values.debugExporter.logs.enabled $supportedSignalCollector (or .Values.logs.enabled .Values.events.enabled) }}
{{- if not (or .Values.debugExporter.metrics.enabled $debugLogsPipeline) }}
{{- fail "lm-otel-container: debugExporter.enabled requires debugExporter.metrics.enabled or an enabled logs/events pipeline" }}
{{- end }}
{{- end }}
{{- if .Values.diagnosticFileExporter.enabled }}
{{- if not (and $supportedSignalCollector (or .Values.logs.enabled .Values.events.enabled)) }}
{{- fail "lm-otel-container: diagnosticFileExporter.enabled requires logs.enabled or events.enabled" }}
{{- end }}
{{- if not .Values.diagnosticFileExporter.path }}
{{- fail "lm-otel-container: diagnosticFileExporter.path is required when diagnosticFileExporter.enabled=true" }}
{{- end }}
{{- end }}
{{- include "lm-otel-container.filtering.validate" . }}
{{- end }}

{{/*
OTTL helper: (ns == "a") or (ns == "b") for namespace allowlist membership
*/}}
{{- define "lm-otel-container.ottlNamespaceOrEquals" -}}
({{- range $i, $n := . }}{{ if $i }} or {{ end }}resource.attributes["k8s.namespace.name"] == {{ $n | quote }}{{ end }})
{{- end }}


{{/*
YAML list items for cluster collector metrics pipeline receivers.
*/}}
{{- define "lm-otel-container.clusterMetricsReceivers" }}
            - prometheus/ksm
{{- if and .Values.controlPlaneMonitoring.enabled .Values.controlPlaneMonitoring.components.controlPlane.enabled (or .Values.controlPlaneMonitoring.components.controlPlane.apiserver .Values.controlPlaneMonitoring.components.controlPlane.scheduler .Values.controlPlaneMonitoring.components.controlPlane.controllerManager .Values.controlPlaneMonitoring.components.controlPlane.etcd) }}
            - prometheus/control-plane
{{- end }}
{{- if and .Values.controlPlaneMonitoring.enabled .Values.controlPlaneMonitoring.components.coredns.enabled }}
            - prometheus/coredns
{{- end }}
{{- if and .Values.controlPlaneMonitoring.enabled .Values.controlPlaneMonitoring.components.kubeProxy.enabled }}
            - prometheus/kube-proxy
{{- end }}
{{- if .Values.collectorMetrics.enabled }}
            - prometheus/self
{{- end }}
{{- end }}

{{/*
Resolved LogicMonitor portal subdomain (portalName).
*/}}
{{- define "lm-otel-container.account" -}}
{{- .Values.portalName }}
{{- end }}

{{/*
Absolute path where the OTel ConfigMap is mounted as a single file (subPath: config.yaml).
The container binary (createCollector) looks up external config at Getwd() + "/external_config.yaml".
The lm-otel image WORKDIR is /opt/logicmonitor, so the effective path is
/opt/logicmonitor/external_config.yaml. K8S_CONFIG_PATH uses the same file for lmotel.
*/}}
{{- define "lm-otel-container.configMountPath" -}}
/opt/logicmonitor/external_config.yaml
{{- end }}

{{/*
Full --config argument passed to the collector container.
For otel-collector-contrib this is consumed directly. For lm-otel, entrypoint.sh
starts lmotel with its generated config first; the file: form is passed through
and overlays the mounted Helm config so fields unsupported by createCollector are
still present in the effective Collector config.
*/}}
{{- define "lm-otel-container.configArgs" -}}
{{- if eq .Values.collector.type "lm-otel" -}}
--config=file:{{ include "lm-otel-container.configMountPath" . }}
{{- else -}}
--config={{ include "lm-otel-container.configMountPath" . }}
{{- end -}}
{{- end }}

{{/*
Agent (DaemonSet) container image.
  lm-otel -> collector.lmOtelImage
  contrib -> agent.image
*/}}
{{- define "lm-otel-container.agentImage" -}}
{{- if eq .Values.collector.type "lm-otel" -}}
{{ printf "%s:%s" .Values.collector.lmOtelImage.repository .Values.collector.lmOtelImage.tag | quote }}
{{- else -}}
{{ printf "%s:%s" .Values.agent.image.repository .Values.agent.image.tag | quote }}
{{- end -}}
{{- end }}

{{/*
Agent (DaemonSet) image pull policy.
*/}}
{{- define "lm-otel-container.agentImagePullPolicy" -}}
{{- if eq .Values.collector.type "lm-otel" -}}
{{ .Values.collector.lmOtelImage.pullPolicy }}
{{- else -}}
{{ .Values.agent.image.pullPolicy }}
{{- end -}}
{{- end }}

{{/*
Cluster collector StatefulSet container image.
*/}}
{{- define "lm-otel-container.clusterImage" -}}
{{- if eq .Values.collector.type "lm-otel" -}}
{{ printf "%s:%s" .Values.collector.lmOtelImage.repository .Values.collector.lmOtelImage.tag | quote }}
{{- else -}}
{{ printf "%s:%s" .Values.clusterCollector.image.repository .Values.clusterCollector.image.tag | quote }}
{{- end -}}
{{- end }}

{{/*
Cluster collector image pull policy.
*/}}
{{- define "lm-otel-container.clusterImagePullPolicy" -}}
{{- if eq .Values.collector.type "lm-otel" -}}
{{ .Values.collector.lmOtelImage.pullPolicy }}
{{- else -}}
{{ .Values.clusterCollector.image.pullPolicy }}
{{- end -}}
{{- end }}

{{/*
Common environment variables injected into every collector container.
Includes all variables required by the lm-otel binary (lmotel) and by OTel
config YAML via ${env:...} substitution.
*/}}
{{- define "lm-otel-container.commonEnv" -}}
- name: LOGICMONITOR_ACCOUNT
  value: {{ include "lm-otel-container.account" . | quote }}
- name: LOGICMONITOR_DOMAIN
  value: {{ .Values.portalDomain | default "logicmonitor.com" | quote }}
- name: LM_BEARER_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ include "lm-otel-container.secretName" . }}
      key: {{ .Values.auth.secretKey }}
- name: LOGICMONITOR_BEARER_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ include "lm-otel-container.secretName" . }}
      key: {{ .Values.auth.secretKey }}
- name: LOGICMONITOR_OTEL_VERSION
  value: {{ .Values.otel.lmOtelVersion | quote }}
- name: CLUSTER_NAME
  value: {{ .Values.clusterName | quote }}
- name: K8S_LOG_LEVEL
  value: {{ .Values.otel.logLevel | quote }}
{{- if eq .Values.collector.type "lm-otel" }}
- name: K8S_MODE
  value: "true"
- name: K8S_CONFIG_PATH
  value: {{ include "lm-otel-container.configMountPath" . | quote }}
{{- end }}
{{- end }}

{{/*
UID/GID used by the init container that prepares filelog offset storage.
*/}}
{{- define "lm-otel-container.filelogStorageRunAsUser" -}}
{{- if eq .Values.collector.type "lm-otel" -}}
{{ .Values.agent.lmOtelRunAsUser }}
{{- else -}}
{{ .Values.agent.otelContribRunAsUser }}
{{- end -}}
{{- end }}

{{- define "lm-otel-container.filelogStorageRunAsGroup" -}}
{{- if eq .Values.collector.type "lm-otel" -}}
{{ .Values.agent.lmOtelRunAsGroup }}
{{- else -}}
{{ .Values.agent.otelContribRunAsGroup }}
{{- end -}}
{{- end }}

{{- define "lm-otel-container.filelogStorageInitImage" -}}
{{ printf "%s:%s" .Values.agent.filelogStorageInitImage.repository .Values.agent.filelogStorageInitImage.tag | quote }}
{{- end }}
