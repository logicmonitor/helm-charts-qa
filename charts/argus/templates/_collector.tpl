{{- define "argus.custom-collector-pod-sec-context-nonroot" }}
{{- toYaml .Values.collector.podSecurityContext | nindent 0 }}
{{- end }}
{{- define "argus.collector-pod-sec-context-nonroot" -}}
{{- include "lmutil.merge" (append . "argus.collector-default-pod-sec-context-nonroot" ) -}}
{{- end -}}

{{- define "argus.custom-collector-container-sec-context-nonroot" }}
{{- $addCaps := .Values.collector.securityContext.capabilities.add }}

{{- if and (eq (include "lmutil.get-platform" .) "gke") (not (has "NET_RAW" $addCaps)) }}
{{- $addCaps = append $addCaps "NET_RAW" }}
{{- end }}

{{- if (eq (include "lmutil.is-openshift" .) "true")  }}
{{- if not (has "NET_RAW" $addCaps) }}
{{- $addCaps = append $addCaps "NET_RAW" }}
{{- end }}
{{- if not (has "SETFCAP" $addCaps) }}
{{- $addCaps = append $addCaps "SETFCAP" }}
{{- end }}
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

{{- define "argus.collector-affinity" }}
{{ if .Values.collector.affinity }}
  {{- toYaml .Values.collector.affinity | nindent 4 }}
{{ else if not .Values.collector.allowMultipleCollectorsOnNode }}
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/name: collectorset
            app.kubernetes.io/instance: {{ include "lmutil.fullname" . }}
        topologyKey: kubernetes.io/hostname
{{ else }}
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 50
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: collectorset
              app.kubernetes.io/instance: {{ include "lmutil.fullname" . }}
          topologyKey : kubernetes.io/hostname
{{ end }}
{{- end }}

{{- define "argus.collector-default-container-sec-context-nonroot" }}
{{- if eq (include "lmutil.is-openshift" .) "true" }}
{{ $caps := .Values.collector.securityContext.capabilities.add }}
{{- if not (has "NET_RAW" $caps) }}
{{- $caps = append $caps "NET_RAW" }}
{{- end }}
{{- if not (has "SETFCAP" $caps) }}
{{- $caps = append $caps "SETFCAP" }}
{{- end }}
allowPrivilegeEscalation: true
capabilities:
  add: {{ toYaml $caps | nindent 4 }}
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

{{/* This template is used for validating COLLECTOR_NON_ROOT env variable, please do not print anything here */}}
{{- define "non-root-prop-check"}}
{{$isKeyInvalid := false}}
{{$isValueInvalid := false}}
{{- $trueCheckList := list "true" "1" "True" "yes" "Yes"}}
{{- $falseCheckList := list "false" "0" "False" "no" "No"}}
{{- if not (empty .Values.collector.env)}}
{{- range $key, $value := .Values.collector.env }}
    {{- if eq (upper $key) "COLLECTOR_NON_ROOT"}}
        {{- if eq $key "COLLECTOR_NON_ROOT"}}
            {{- if and (not (empty $value)) (not (or (has $value $falseCheckList) (has $value $trueCheckList))) }}
            {{- $isValueInvalid = true}}
            {{- end}}
        {{- else }}
            {{- $isKeyInvalid = true}}
        {{- end }}
    {{- end}}
{{- end}}
{{- if $isKeyInvalid }}
{{- fail (printf "COLLECTOR_NON_ROOT param is case sensitive, please check your configurations.") }}
{{- end}}
{{- if $isValueInvalid }}
{{- fail (printf "Please provide a valid boolean value for COLLECTOR_NON_ROOT param")}}
{{- end}}
{{- end}}
{{- end}}