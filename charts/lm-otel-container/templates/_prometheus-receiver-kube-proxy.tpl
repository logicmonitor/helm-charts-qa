{{/*
prometheus/kube-proxy receiver — kube-proxy pods in kube-system.
*/}}
{{- define "lm-otel-container.prometheusReceiverKubeProxy" -}}
prometheus/kube-proxy:
  config:
    scrape_configs:
      - job_name: kube-proxy
        scrape_interval: {{ .Values.controlPlaneMonitoring.scrapeInterval }}
        kubernetes_sd_configs:
          - role: pod
            namespaces:
              names: [kube-system]
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_label_k8s_app]
            action: keep
            regex: kube-proxy
          - source_labels: [__meta_kubernetes_pod_ip]
            target_label: __address__
            replacement: $1:10249
{{- end }}
