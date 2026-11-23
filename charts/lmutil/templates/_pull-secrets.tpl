{{- define "lmutil.openshift-pull-secrets.enabled" -}}
{{- if and (eq (include "lmutil.is-openshift" .) "true") (dig "openshiftPullSecrets" "enabled" false .Values.global) -}}
true
{{- end -}}
{{- end -}}

{{- define "lmutil.openshift-pull-secrets.field" -}}
{{- $context := index . 0 -}}
{{- $name := index . 1 -}}
{{- $namespace := index . 2 -}}
{{- $desired := index . 3 -}}
{{- $clientSide := index . 4 -}}
{{- if and $clientSide (or $desired (lookup "v1" "ServiceAccount" $namespace $name)) }}
imagePullSecrets:
  {{- include "lmutil.openshift-pull-secrets.values" (list $context $name $namespace $desired) | nindent 2 }}
{{- end -}}
{{- end -}}

{{- define "lmutil.openshift-pull-secrets.client-side" -}}
{{- $context := index . 0 -}}
{{- $name := index . 1 -}}
{{- $namespace := index . 2 -}}
{{- $account := lookup "v1" "ServiceAccount" $namespace $name | default dict -}}
{{- $mode := dig "metadata" "annotations" "logicmonitor.com/pull-secrets-apply-mode" "" $account -}}
{{- $clientSide := or (lt (int (semver $context.Capabilities.HelmVersion.Version).Major) 4) (eq $mode "client") -}}
{{- if and (not $account) $context.Release.IsUpgrade -}}
{{- $configName := printf "%s-pull-secrets" ($context.Release.Name | trunc 40 | trimSuffix "-") -}}
{{- $config := lookup "v1" "ConfigMap" $context.Release.Namespace $configName | default dict -}}
{{- $raw := dig "data" "targets.json" "" $config -}}
{{- if $raw -}}
{{- $settings := fromJson $raw -}}
{{- if and (hasKey $settings "createAccounts") (not $settings.createAccounts) -}}
{{- $clientSide = true -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if eq $mode "" -}}
{{- range (dig "metadata" "managedFields" list $account) -}}
{{- if and (eq .manager "helm") (eq .operation "Update") -}}
{{- $clientSide = true -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if $clientSide -}}true{{- end -}}
{{- end -}}

{{- define "lmutil.openshift-pull-secrets.values" -}}
{{- $context := index . 0 -}}
{{- $name := index . 1 -}}
{{- $namespace := index . 2 -}}
{{- $desired := index . 3 -}}
{{- $account := lookup "v1" "ServiceAccount" $namespace $name | default dict -}}
{{- $owned := fromJsonArray (dig "metadata" "annotations" "logicmonitor.com/managed-pull-secrets" "[]" $account) -}}
{{- $platform := dig "metadata" "annotations" "openshift.io/internal-registry-pull-secret-ref" "" $account -}}
{{- $combined := list -}}
{{- $seen := dict -}}
{{- range ($account.imagePullSecrets | default list) -}}
{{- if or (not (has .name $owned)) (eq .name $platform) -}}
{{- $combined = append $combined (dict "name" .name) -}}
{{- $_ := set $seen .name true -}}
{{- end -}}
{{- end -}}
{{- range $desired -}}
{{- $secretName := . -}}
{{- if kindIs "map" . -}}{{- $secretName = .name -}}{{- end -}}
{{- if not (hasKey $seen $secretName) -}}
{{- $combined = append $combined (dict "name" $secretName) -}}
{{- $_ := set $seen $secretName true -}}
{{- end -}}
{{- end -}}
{{- if and $platform (not (hasKey $seen $platform)) -}}
{{- $combined = append $combined (dict "name" $platform) -}}
{{- end -}}
{{- toYaml $combined -}}
{{- end -}}
