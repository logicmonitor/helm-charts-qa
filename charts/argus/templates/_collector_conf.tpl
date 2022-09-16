{{/* vim: set filetype=mustache: */}}

{{- define "trimmed-collector-config-agentConf" -}}
{{- $trimmedCollectorProps := list "jdbc" "perfmon" "wmi" "netapp" "esx" "xen" "mongo" "wineventlog" "snmptrap" "syslog"}}
{{- $propList := list  }}
{{- range $val := $trimmedCollectorProps }}
{{- $kv := dict}}
{{- $_ := set $kv "key" (printf "collector.%s.enable" $val) }}
{{- $_1 := set $kv "value" "false" }}
{{- $propList = append $propList $kv }}
trimmedCollectorAgentConf:
{{- toYaml $propList | nindent 2 }}
{{- end }}
{{- end }}