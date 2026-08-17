{{/*
All prometheus/* receivers for the cluster collector config.yaml.
*/}}
{{- define "lm-otel-container.clusterReceiversBlock" -}}
{{ include "lm-otel-container.prometheusReceiverKsm" . | nindent 6 }}
{{- if and .Values.controlPlaneMonitoring.enabled .Values.controlPlaneMonitoring.components.controlPlane.enabled (or .Values.controlPlaneMonitoring.components.controlPlane.apiserver .Values.controlPlaneMonitoring.components.controlPlane.scheduler .Values.controlPlaneMonitoring.components.controlPlane.controllerManager .Values.controlPlaneMonitoring.components.controlPlane.etcd) }}
{{ include "lm-otel-container.prometheusReceiverControlPlane" . | nindent 6 }}
{{- end }}
{{- if and .Values.controlPlaneMonitoring.enabled .Values.controlPlaneMonitoring.components.coredns.enabled }}
{{ include "lm-otel-container.prometheusReceiverCoredns" . | nindent 6 }}
{{- end }}
{{- if and .Values.controlPlaneMonitoring.enabled .Values.controlPlaneMonitoring.components.kubeProxy.enabled }}
{{ include "lm-otel-container.prometheusReceiverKubeProxy" . | nindent 6 }}
{{- end }}
{{- if .Values.collectorMetrics.enabled }}
{{ include "lm-otel-container.prometheusReceiverSelf" (dict "root" . "jobName" "otel-collector-cluster") | nindent 6 }}
{{- end }}
{{- end }}
