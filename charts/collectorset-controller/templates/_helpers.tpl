{{/* vim: set filetype=mustache: */}}

{{/*
Common labels
*/}}
{{- define "collectorset-controller.labels" -}}
{{ include "lmutil.generic.labels" . }}
app.kubernetes.io/component: custom-resource-controller
{{/*
Adding app property to make it backward compatible in trasition phase.
New datasources or existing datasources should use app.kubernetes.io/name property in its appliesto script
*/}}
app: collectorset-controller
{{ include "lmutil.selectorLabels" . }}
{{- if .Values.labels }}
{{ toYaml .Values.labels }}
{{- end }}
{{- end }}


{{/*
Common Annotations
*/}}
{{- define "collectorset-controller.annotations" -}}
logicmonitor.com/provider: lm-container
{{- if .Values.annotations }}
{{ toYaml .Values.annotations }}
{{- end }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "collectorset-controller.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "lmutil.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "csc-image" -}}
{{- $registry := "" -}}
{{- $repo := "logicmonitor" -}}
{{- if .Values.image.registry -}}
{{- $registry = .Values.image.registry -}}
{{- else if .Values.global.image.registry -}}
{{- $registry = .Values.global.image.registry -}}
{{- end -}}
{{- if .Values.image.repository -}}
{{- $repo = .Values.image.repository -}}
{{- else if .Values.global.image.repository -}}
{{- $repo = .Values.global.image.repository -}}
{{- end -}}
{{- if ne $registry "" -}}
"{{ $registry }}/{{ $repo }}/{{ .Values.image.name }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
{{- else -}}
"{{ $repo }}/{{ .Values.image.name }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
{{- end -}}
{{- end -}}

{{/*
LM Credentials and Proxy Details.
envconfig prefix is "collectorset-controller"; primary keys look like COLLECTORSET-CONTROLLER_ACCOUNT but
hyphens in env names are unreliable in some runtimes. Use envconfig's alternate keys (envconfig tag value),
which match what Process() looks up second — same as ACCESS_ID, ACCOUNT, COMPANY_DOMAIN, CSC_PROXY_USER, etc.
*/}}

{{- define "lm-credentials-and-proxy-details" -}}
- name: ACCESS_ID
  valueFrom:
    secretKeyRef:
      name: {{ include "lmutil.secret-name" . }}
      key: accessID
- name: ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "lmutil.secret-name" . }}
      key: accessKey
- name: ACCOUNT
  valueFrom:
    secretKeyRef:
      name: {{ include "lmutil.secret-name" . }}
      key: account
- name: COMPANY_DOMAIN
  valueFrom:
    secretKeyRef:
      name: {{ include "lmutil.secret-name" . }}
      key: companyDomain
      optional: true
- name: PROXY_USER
  valueFrom:
    secretKeyRef:
      name: {{ include "lmutil.secret-name" . }}
      key: proxyUser
      optional: true
- name: PROXY_PASS
  valueFrom:
    secretKeyRef:
      name: {{ include "lmutil.secret-name" . }}
      key: proxyPass
      optional: true
- name: CSC_PROXY_USER
  valueFrom:
    secretKeyRef:
      name: {{ include "lmutil.secret-name" . }}
      key: cscProxyUser
      optional: true
- name: CSC_PROXY_PASS
  valueFrom:
    secretKeyRef:
      name: {{ include "lmutil.secret-name" . }}
      key: cscProxyPass
      optional: true
{{- end }}