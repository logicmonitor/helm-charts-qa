{{- define "lm-container.pull-secrets.name" -}}
{{- printf "%s-pull-secrets" (.Release.Name | trunc 40 | trimSuffix "-") -}}
{{- end -}}

{{- define "lm-container.pull-secrets.targets" -}}
{{- $targets := list -}}
{{- range $component := list "argus" "collectorset-controller" "kube-state-metrics" -}}
{{- with index $.Subcharts $component -}}
{{- if .Values.serviceAccount.create -}}
{{- $nameHelper := "lmutil.serviceAccountName" -}}
{{- $namespaceHelper := "lmutil.release.namespace" -}}
{{- $local := .Values.imagePullSecrets | default list -}}
{{- if eq $component "collectorset-controller" -}}
{{- $nameHelper = "collectorset-controller.serviceAccountName" -}}
{{- else if eq $component "kube-state-metrics" -}}
{{- $nameHelper = "kube-state-metrics.serviceAccountName" -}}
{{- $namespaceHelper = "kube-state-metrics.namespace" -}}
{{- $local = .Values.serviceAccount.imagePullSecrets | default list -}}
{{- end -}}
{{- $name := include $nameHelper . -}}
{{- $namespace := include $namespaceHelper . -}}
{{- $secrets := concat $local (.Values.global.imagePullSecrets | default list) | uniq -}}
{{- $clientSide := eq (include "lmutil.openshift-pull-secrets.client-side" (list . $name $namespace)) "true" -}}
{{- $targets = append $targets (dict "name" $name "namespace" $namespace "secrets" $secrets "clientSide" $clientSide) -}}
{{- if eq $component "collectorset-controller" -}}
{{- $collectorName := printf "%s-collector" $name -}}
{{- $targets = append $targets (dict "name" $collectorName "namespace" $namespace "secrets" $secrets "clientSide" (eq (include "lmutil.openshift-pull-secrets.client-side" (list . $collectorName $namespace)) "true")) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- toJson (dict "targets" $targets) -}}
{{- end -}}

{{- define "lm-container.pull-secrets.config" -}}
{{- $targets := (include "lm-container.pull-secrets.targets" . | fromJson).targets -}}
{{- $namespaces := list .Release.Namespace -}}
{{- $clientSide := false -}}
{{- range $targets -}}
{{- $namespaces = append $namespaces .namespace -}}
{{- if .clientSide -}}{{- $clientSide = true -}}{{- end -}}
{{- end -}}
{{- toJson (dict "release" .Release.Name "releaseNamespace" .Release.Namespace "targets" $targets "namespaces" ($namespaces | uniq) "createAccounts" (not $clientSide) "intervalSeconds" .Values.openshiftPullSecrets.intervalSeconds "configName" (include "lm-container.pull-secrets.name" .) "bootstrapName" (printf "%s-bootstrap" (include "lm-container.pull-secrets.name" .))) -}}
{{- end -}}

{{- define "lm-container.pull-secrets.pod" -}}
{{- $root := .root -}}
{{- $name := .name -}}
serviceAccountName: {{ $name }}
restartPolicy: {{ default "Always" .restartPolicy }}
terminationGracePeriodSeconds: 5
securityContext:
  {{- toYaml (mergeOverwrite (dict "runAsNonRoot" true "seccompProfile" (dict "type" "RuntimeDefault")) ($root.Values.openshiftPullSecrets.podSecurityContext | default dict)) | nindent 2 }}
containers:
  - name: reconcile
    image: {{ $root.Values.openshiftPullSecrets.image | quote }}
    imagePullPolicy: {{ $root.Values.openshiftPullSecrets.imagePullPolicy }}
    command: ["python3", "-B", "/config/reconcile.py"]
    {{- with .args }}
    args: {{ toJson . }}
    {{- end }}
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
    resources:
      {{- toYaml $root.Values.openshiftPullSecrets.resources | nindent 6 }}
    {{- if not .args }}
    readinessProbe:
      exec:
        command: ["sh", "-c", "test -f /state/ready"]
      initialDelaySeconds: 2
      periodSeconds: 5
    {{- end }}
    volumeMounts:
      - name: config
        mountPath: /config
        readOnly: true
      - name: state
        mountPath: /state
volumes:
  - name: config
    configMap:
      name: {{ .configName | default $name }}
  - name: state
    emptyDir: {}
{{- end -}}
