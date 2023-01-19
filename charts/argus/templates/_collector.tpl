{{- define "argus.custom-collector-pod-sec-context-nonroot" }}
{{- toYaml .Values.collector.podSecurityContext | nindent 0 }}
{{- end }}
{{- define "argus.collector-pod-sec-context-nonroot" -}}
{{- include "lmutil.merge" (append . "argus.collector-default-pod-sec-context-nonroot" ) -}}
{{- end -}}

{{- define "argus.custom-collector-container-sec-context-nonroot" }}
{{- $addCaps := .Values.collector.securityContext.capabilities.add }}
{{- if and (or (eq (include "lmutil.get-platform" .) "gke") (eq (include "lmutil.is-openshift" .) "true")) (not (has "NET_RAW" $addCaps)) }}
{{- $addCaps = append $addCaps "NET_RAW" }}
{{- end }}
{{- with .Values.collector.securityContext }}
{{- if not (hasKey . "capabilities") }}
{{ toYaml . | nindent 0 }}
{{- end }}
{{- end }}
capabilities:
  drop: {{ toYaml .Values.collector.securityContext.capabilities.drop | nindent 4 }}
  add: {{ toYaml $addCaps | nindent 4 }}
{{- end }}
{{- define "argus.collector-container-sec-context-nonroot" -}}
{{- include "lmutil.merge" (append . "argus.collector-default-container-sec-context-nonroot" ) -}}
{{- end -}}

{{- define "argus.collector-default-pod-sec-context-nonroot" }}
{{ if eq (include "lmutil.is-openshift" .) "true" }}
{{ if and (hasKey .Values.collector.env "COLLECTOR_NON_ROOT") (eq .Values.collector.env.COLLECTOR_NON_ROOT "true")  }}
runAsUser: 2000
fsGroup: 2000
runAsGroup: 2000
runAsNonRoot: true
{{ else }}
runAsUser: 0
fsGroup: 0
runAsGroup: 0
runAsNonRoot: false
{{ end }}
{{- end }}
{{- end }}


{{- define "argus.collector-default-container-sec-context-nonroot" }}
{{- if eq (include "lmutil.is-openshift" .) "true" }}
allowPrivilegeEscalation: true
capabilities:
  add:
    - NET_RAW
{{- range .Values.collector.securityContext.capabilities.add }}
    {{- if ne "NET_RAW" . }}
    - {{ . }}
    {{- end }}
{{- end }}
{{- end }}
{{- if eq (include "lmutil.get-platform" .) "gke" }}
capabilities:
  add:
    - NET_RAW
{{- range .Values.collector.securityContext.capabilities.add }}
    {{- if ne "NET_RAW" . }}
    - {{ . }}
    {{- end }}
{{- end }}
{{- end }}
{{- end }}
