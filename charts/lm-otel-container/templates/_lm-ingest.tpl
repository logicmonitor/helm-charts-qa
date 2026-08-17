{{/*
LogicMonitor log/event ingest helpers.

Both lmexporter and upstream logicmonitor exporter can send logs directly in
k8s mode. The transforms below still add filename, filepath, logsource
type/name, and LogicMonitor log metadata fields so LogicMonitor ingest receives
consistent records. lmextension is lm-otel-only and loads install.yaml collector
metadata for fleet/log ingest behavior when islogsenabled is true.
*/}}

{{/*
lmextension block - include under extensions for lm-otel fleet/log ingest behavior.
Omit filepath to use the default install.yaml next to the lmotel binary (../config/install.yaml).
*/}}
{{- define "lm-otel-container.lmExtension" -}}
lmextension:
  backend:
    endpoint: https://${env:LOGICMONITOR_ACCOUNT}.${env:LOGICMONITOR_DOMAIN}/santaba/api
  islogsenabled: true
  properties:
    system.collector.type: otel
    type: opentelemetry
{{- end }}

{{/*
Map filelog attributes to the fields LogicMonitor log ingest can use.
logSourceId is optional in k8s mode and is rendered only when explicitly
configured.
*/}}
{{- define "lm-otel-container.transformLmFilelog" -}}
transform/lm_filelog:
  error_mode: ignore
  log_statements:
    - context: log
      statements:
        - set(attributes["type"], {{ default "logs" .Values.logs.type | quote }})
        - set(attributes["logtype"], {{ default "container_logs" .Values.logs.logType | quote }})
        - set(attributes["filename"], attributes["log.file.path"]) where attributes["filename"] == nil and attributes["log.file.path"] != nil
        - set(attributes["filename"], attributes["log.file.name"]) where attributes["filename"] == nil and attributes["log.file.name"] != nil
        - set(attributes["_filepath"], attributes["filename"]) where attributes["filename"] != nil
        - set(attributes["_lm.logsource_type"], "logfile")
        - set(attributes["k8s_cluster_name"], resource.attributes["cluster_name"]) where resource.attributes["cluster_name"] != nil
        - set(attributes["k8s_collector_name"], resource.attributes["lm.collector.name"]) where resource.attributes["lm.collector.name"] != nil
        - set(attributes["k8s_service_name"], resource.attributes["service.name"]) where resource.attributes["service.name"] != nil
        - set(attributes["k8s_app_name"], resource.attributes["kubernetes.label.app.kubernetes.io/name"]) where resource.attributes["kubernetes.label.app.kubernetes.io/name"] != nil
        - set(attributes["k8s_app_version"], resource.attributes["kubernetes.label.app.kubernetes.io/version"]) where resource.attributes["kubernetes.label.app.kubernetes.io/version"] != nil
        - set(attributes["k8s_app_instance"], resource.attributes["kubernetes.label.app.kubernetes.io/instance"]) where resource.attributes["kubernetes.label.app.kubernetes.io/instance"] != nil
        - set(attributes["k8s_otel_name"], resource.attributes["kubernetes.label.opentelemetry.io/name"]) where resource.attributes["kubernetes.label.opentelemetry.io/name"] != nil
        - set(attributes["k8s_app_component"], resource.attributes["kubernetes.label.app.kubernetes.io/component"]) where resource.attributes["kubernetes.label.app.kubernetes.io/component"] != nil
        - set(attributes["k8s_app_part_of"], resource.attributes["kubernetes.label.app.kubernetes.io/part-of"]) where resource.attributes["kubernetes.label.app.kubernetes.io/part-of"] != nil
        - set(attributes["k8s_app_managed_by"], resource.attributes["kubernetes.label.app.kubernetes.io/managed-by"]) where resource.attributes["kubernetes.label.app.kubernetes.io/managed-by"] != nil
        - set(attributes["k8s_helm_chart"], resource.attributes["kubernetes.label.helm.sh/chart"]) where resource.attributes["kubernetes.label.helm.sh/chart"] != nil
        - set(attributes["k8s_label_app"], resource.attributes["kubernetes.label.app"]) where resource.attributes["kubernetes.label.app"] != nil
        - set(attributes["k8s_label_k8s_app"], resource.attributes["kubernetes.label.k8s-app"]) where resource.attributes["kubernetes.label.k8s-app"] != nil
        - set(attributes["k8s_namespace"], resource.attributes["k8s.namespace.name"]) where resource.attributes["k8s.namespace.name"] != nil
        - set(attributes["k8s_pod_name"], resource.attributes["k8s.pod.name"]) where resource.attributes["k8s.pod.name"] != nil
        - set(attributes["k8s_pod_uid"], resource.attributes["k8s.pod.uid"]) where resource.attributes["k8s.pod.uid"] != nil
        - set(attributes["k8s_pod_ip"], resource.attributes["k8s.pod.ip"]) where resource.attributes["k8s.pod.ip"] != nil
        - set(attributes["k8s_pod_hostname"], resource.attributes["k8s.pod.hostname"]) where resource.attributes["k8s.pod.hostname"] != nil
        - set(attributes["k8s_pod_start_time"], resource.attributes["k8s.pod.start_time"]) where resource.attributes["k8s.pod.start_time"] != nil
        - set(attributes["k8s_node_name"], resource.attributes["k8s.node.name"]) where resource.attributes["k8s.node.name"] != nil and resource.attributes["k8s.node.name"] != ""
        - set(attributes["k8s_node_uid"], resource.attributes["k8s.node.uid"]) where resource.attributes["k8s.node.uid"] != nil
        - set(attributes["k8s_container_name"], resource.attributes["k8s.container.name"]) where resource.attributes["k8s.container.name"] != nil
        - set(attributes["k8s_container_restart_count"], resource.attributes["k8s.container.restart_count"]) where resource.attributes["k8s.container.restart_count"] != nil
        - set(attributes["k8s_container_image_name"], resource.attributes["container.image.name"]) where resource.attributes["container.image.name"] != nil
        - set(attributes["k8s_container_image_tag"], resource.attributes["container.image.tag"]) where resource.attributes["container.image.tag"] != nil
        - set(attributes["k8s_deployment_name"], resource.attributes["k8s.deployment.name"]) where resource.attributes["k8s.deployment.name"] != nil
        - set(attributes["k8s_deployment_uid"], resource.attributes["k8s.deployment.uid"]) where resource.attributes["k8s.deployment.uid"] != nil
        - set(attributes["k8s_replicaset_name"], resource.attributes["k8s.replicaset.name"]) where resource.attributes["k8s.replicaset.name"] != nil
        - set(attributes["k8s_replicaset_uid"], resource.attributes["k8s.replicaset.uid"]) where resource.attributes["k8s.replicaset.uid"] != nil
        - set(attributes["k8s_statefulset_name"], resource.attributes["k8s.statefulset.name"]) where resource.attributes["k8s.statefulset.name"] != nil
        - set(attributes["k8s_statefulset_uid"], resource.attributes["k8s.statefulset.uid"]) where resource.attributes["k8s.statefulset.uid"] != nil
        - set(attributes["k8s_daemonset_name"], resource.attributes["k8s.daemonset.name"]) where resource.attributes["k8s.daemonset.name"] != nil
        - set(attributes["k8s_daemonset_uid"], resource.attributes["k8s.daemonset.uid"]) where resource.attributes["k8s.daemonset.uid"] != nil
        - set(attributes["k8s_job_name"], resource.attributes["k8s.job.name"]) where resource.attributes["k8s.job.name"] != nil
        - set(attributes["k8s_job_uid"], resource.attributes["k8s.job.uid"]) where resource.attributes["k8s.job.uid"] != nil
        - set(attributes["k8s_cronjob_name"], resource.attributes["k8s.cronjob.name"]) where resource.attributes["k8s.cronjob.name"] != nil
        - set(attributes["k8s_cronjob_uid"], resource.attributes["k8s.cronjob.uid"]) where resource.attributes["k8s.cronjob.uid"] != nil
{{- if .Values.logs.logSourceId }}
        - set(attributes["_lm.logsource_id"], {{ .Values.logs.logSourceId | quote }})
{{- end }}
{{- if .Values.logs.logSourceName }}
        - set(attributes["_lm.logsource_name"], {{ default "k8s-container-logs" .Values.logs.logSourceName | quote }})
{{- end }}
{{- end }}

{{/*
Prepare Pod-scoped Kubernetes Events for k8sattributes enrichment. The events
receiver stores involved object data as k8s.object.* resource attributes; for
Pod events, mirror the object identity into k8s.pod.* before k8sattributes runs.
*/}}
{{- define "lm-otel-container.transformLmK8sEventPodAttrs" -}}
transform/lm_k8s_event_pod_attrs:
  error_mode: ignore
  log_statements:
    - context: log
      statements:
        - set(resource.attributes["k8s.namespace.name"], attributes["k8s.namespace.name"]) where resource.attributes["k8s.object.kind"] == "Pod" and attributes["k8s.namespace.name"] != nil
        - set(resource.attributes["k8s.pod.name"], resource.attributes["k8s.object.name"]) where resource.attributes["k8s.object.kind"] == "Pod" and resource.attributes["k8s.object.name"] != nil
        - set(resource.attributes["k8s.pod.uid"], resource.attributes["k8s.object.uid"]) where resource.attributes["k8s.object.kind"] == "Pod" and resource.attributes["k8s.object.uid"] != nil
        - set(resource.attributes["k8s.container.name"], resource.attributes["k8s.object.fieldpath"]) where resource.attributes["k8s.object.kind"] == "Pod" and resource.attributes["k8s.object.fieldpath"] != nil and resource.attributes["k8s.object.fieldpath"] != ""
        - replace_pattern(resource.attributes["k8s.container.name"], "^spec\\.containers\\{([^}]*)\\}$", "$1") where resource.attributes["k8s.container.name"] != nil
{{- end }}

{{/*
k8seventsreceiver emits event messages as log bodies. Synthesize a filename and
optional logsource fields for LogicMonitor log ingest compatibility.
*/}}
{{- define "lm-otel-container.transformLmK8sEvents" -}}
transform/lm_k8s_events:
  error_mode: ignore
  log_statements:
    - context: log
      statements:
        - set(attributes["type"], {{ default "events" .Values.events.type | quote }})
        - set(attributes["filename"], {{ default "/var/log/kubernetes/events.log" .Values.events.syntheticFilename | quote }})
        - set(attributes["_filepath"], attributes["filename"]) where attributes["filename"] != nil
        - set(attributes["_lm.logsource_type"], "logfile")
        - set(attributes["k8s_cluster_name"], resource.attributes["cluster_name"]) where resource.attributes["cluster_name"] != nil
        - set(attributes["k8s_collector_name"], resource.attributes["lm.collector.name"]) where resource.attributes["lm.collector.name"] != nil
        - set(attributes["k8s_app_name"], resource.attributes["kubernetes.label.app.kubernetes.io/name"]) where resource.attributes["kubernetes.label.app.kubernetes.io/name"] != nil
        - set(attributes["k8s_app_version"], resource.attributes["kubernetes.label.app.kubernetes.io/version"]) where resource.attributes["kubernetes.label.app.kubernetes.io/version"] != nil
        - set(attributes["k8s_app_instance"], resource.attributes["kubernetes.label.app.kubernetes.io/instance"]) where resource.attributes["kubernetes.label.app.kubernetes.io/instance"] != nil
        - set(attributes["k8s_otel_name"], resource.attributes["kubernetes.label.opentelemetry.io/name"]) where resource.attributes["kubernetes.label.opentelemetry.io/name"] != nil
        - set(attributes["k8s_app_component"], resource.attributes["kubernetes.label.app.kubernetes.io/component"]) where resource.attributes["kubernetes.label.app.kubernetes.io/component"] != nil
        - set(attributes["k8s_app_part_of"], resource.attributes["kubernetes.label.app.kubernetes.io/part-of"]) where resource.attributes["kubernetes.label.app.kubernetes.io/part-of"] != nil
        - set(attributes["k8s_app_managed_by"], resource.attributes["kubernetes.label.app.kubernetes.io/managed-by"]) where resource.attributes["kubernetes.label.app.kubernetes.io/managed-by"] != nil
        - set(attributes["k8s_helm_chart"], resource.attributes["kubernetes.label.helm.sh/chart"]) where resource.attributes["kubernetes.label.helm.sh/chart"] != nil
        - set(attributes["k8s_label_app"], resource.attributes["kubernetes.label.app"]) where resource.attributes["kubernetes.label.app"] != nil
        - set(attributes["k8s_label_k8s_app"], resource.attributes["kubernetes.label.k8s-app"]) where resource.attributes["kubernetes.label.k8s-app"] != nil
        - set(attributes["k8s_namespace"], attributes["k8s.namespace.name"]) where attributes["k8s.namespace.name"] != nil
        - set(attributes["k8s_node_name"], resource.attributes["k8s.node.name"]) where resource.attributes["k8s.node.name"] != nil and resource.attributes["k8s.node.name"] != ""
        - set(attributes["k8s_node_uid"], resource.attributes["k8s.node.uid"]) where resource.attributes["k8s.node.uid"] != nil
        - set(attributes["k8s_pod_name"], resource.attributes["k8s.object.name"]) where resource.attributes["k8s.object.kind"] == "Pod" and resource.attributes["k8s.object.name"] != nil
        - set(attributes["k8s_pod_uid"], resource.attributes["k8s.object.uid"]) where resource.attributes["k8s.object.kind"] == "Pod" and resource.attributes["k8s.object.uid"] != nil
        - set(attributes["k8s_pod_ip"], resource.attributes["k8s.pod.ip"]) where resource.attributes["k8s.pod.ip"] != nil
        - set(attributes["k8s_pod_hostname"], resource.attributes["k8s.pod.hostname"]) where resource.attributes["k8s.pod.hostname"] != nil
        - set(attributes["k8s_pod_start_time"], resource.attributes["k8s.pod.start_time"]) where resource.attributes["k8s.pod.start_time"] != nil
        - set(attributes["k8s_container_name"], resource.attributes["k8s.object.fieldpath"]) where resource.attributes["k8s.object.kind"] == "Pod" and resource.attributes["k8s.object.fieldpath"] != nil and resource.attributes["k8s.object.fieldpath"] != ""
        - replace_pattern(attributes["k8s_container_name"], "^spec\\.containers\\{([^}]*)\\}$", "$1") where attributes["k8s_container_name"] != nil
        - set(attributes["k8s_container_image_name"], resource.attributes["container.image.name"]) where resource.attributes["container.image.name"] != nil
        - set(attributes["k8s_container_image_tag"], resource.attributes["container.image.tag"]) where resource.attributes["container.image.tag"] != nil
        - set(attributes["k8s_deployment_name"], resource.attributes["k8s.deployment.name"]) where resource.attributes["k8s.deployment.name"] != nil
        - set(attributes["k8s_deployment_uid"], resource.attributes["k8s.deployment.uid"]) where resource.attributes["k8s.deployment.uid"] != nil
        - set(attributes["k8s_replicaset_name"], resource.attributes["k8s.replicaset.name"]) where resource.attributes["k8s.replicaset.name"] != nil
        - set(attributes["k8s_replicaset_uid"], resource.attributes["k8s.replicaset.uid"]) where resource.attributes["k8s.replicaset.uid"] != nil
        - set(attributes["k8s_statefulset_name"], resource.attributes["k8s.statefulset.name"]) where resource.attributes["k8s.statefulset.name"] != nil
        - set(attributes["k8s_statefulset_uid"], resource.attributes["k8s.statefulset.uid"]) where resource.attributes["k8s.statefulset.uid"] != nil
        - set(attributes["k8s_daemonset_name"], resource.attributes["k8s.daemonset.name"]) where resource.attributes["k8s.daemonset.name"] != nil
        - set(attributes["k8s_daemonset_uid"], resource.attributes["k8s.daemonset.uid"]) where resource.attributes["k8s.daemonset.uid"] != nil
        - set(attributes["k8s_job_name"], resource.attributes["k8s.job.name"]) where resource.attributes["k8s.job.name"] != nil
        - set(attributes["k8s_job_uid"], resource.attributes["k8s.job.uid"]) where resource.attributes["k8s.job.uid"] != nil
        - set(attributes["k8s_cronjob_name"], resource.attributes["k8s.cronjob.name"]) where resource.attributes["k8s.cronjob.name"] != nil
        - set(attributes["k8s_cronjob_uid"], resource.attributes["k8s.cronjob.uid"]) where resource.attributes["k8s.cronjob.uid"] != nil
        - set(attributes["k8s_object_kind"], resource.attributes["k8s.object.kind"]) where resource.attributes["k8s.object.kind"] != nil
        - set(attributes["k8s_object_name"], resource.attributes["k8s.object.name"]) where resource.attributes["k8s.object.name"] != nil
        - set(attributes["k8s_object_uid"], resource.attributes["k8s.object.uid"]) where resource.attributes["k8s.object.uid"] != nil
        - set(attributes["k8s_object_fieldpath"], resource.attributes["k8s.object.fieldpath"]) where resource.attributes["k8s.object.fieldpath"] != nil and resource.attributes["k8s.object.fieldpath"] != ""
        - set(attributes["k8s_object_api_version"], resource.attributes["k8s.object.api_version"]) where resource.attributes["k8s.object.api_version"] != nil
        - set(attributes["k8s_object_resource_version"], resource.attributes["k8s.object.resource_version"]) where resource.attributes["k8s.object.resource_version"] != nil
        - set(attributes["k8s_event_type"], severity_text) where severity_text != ""
        - set(attributes["k8s_event_name"], attributes["k8s.event.name"]) where attributes["k8s.event.name"] != nil
        - set(attributes["k8s_event_reason"], attributes["k8s.event.reason"]) where attributes["k8s.event.reason"] != nil
        - set(attributes["k8s_event_action"], attributes["k8s.event.action"]) where attributes["k8s.event.action"] != nil
        - set(attributes["k8s_event_start_time"], attributes["k8s.event.start_time"]) where attributes["k8s.event.start_time"] != nil
        - set(attributes["k8s_event_count"], attributes["k8s.event.count"]) where attributes["k8s.event.count"] != nil
        - set(attributes["k8s_event_uid"], attributes["k8s.event.uid"]) where attributes["k8s.event.uid"] != nil
        - set(attributes["k8s_event_reporting_controller"], attributes["k8s.event.reporting_controller"]) where attributes["k8s.event.reporting_controller"] != nil
        - set(attributes["k8s_event_reporting_instance"], attributes["k8s.event.reporting_instance"]) where attributes["k8s.event.reporting_instance"] != nil
{{- if .Values.events.logSourceId }}
        - set(attributes["_lm.logsource_id"], {{ .Values.events.logSourceId | quote }})
{{- end }}
{{- if .Values.events.logSourceName }}
        - set(attributes["_lm.logsource_name"], {{ default "k8s-events" .Values.events.logSourceName | quote }})
{{- end }}
{{- end }}

{{/*
lmexporter block shared by lm-otel agent/cluster logs, events, and traces.
*/}}
{{- define "lm-otel-container.lmExporter" -}}
lmexporter:
  url: "https://${env:LOGICMONITOR_ACCOUNT}.${env:LOGICMONITOR_DOMAIN}/rest"
  headers:
    Authorization: "Bearer ${env:LOGICMONITOR_BEARER_TOKEN}"
{{- end }}

{{/*
Upstream OpenTelemetry Collector Contrib LogicMonitor exporter.
Used for logs, Kubernetes Events, and traces when collector.type is
otel-collector-contrib. Fleet management remains lm-otel/lmextension only.
*/}}
{{- define "lm-otel-container.logicmonitorContribExporter" -}}
logicmonitor:
  endpoint: "https://${env:LOGICMONITOR_ACCOUNT}.${env:LOGICMONITOR_DOMAIN}/rest"
  headers:
    Authorization: "Bearer ${env:LOGICMONITOR_BEARER_TOKEN}"
  logs:
    resource_mapping_op: "OR"
{{- end }}

{{- define "lm-otel-container.logicmonitorSignalExporter" -}}
{{- if eq .Values.collector.type "lm-otel" -}}
{{ include "lm-otel-container.lmExporter" . }}
{{- else -}}
{{ include "lm-otel-container.logicmonitorContribExporter" . }}
{{- end -}}
{{- end }}

{{- define "lm-otel-container.logicmonitorSignalExporterName" -}}
{{- if eq .Values.collector.type "lm-otel" -}}
lmexporter
{{- else -}}
logicmonitor
{{- end -}}
{{- end }}
