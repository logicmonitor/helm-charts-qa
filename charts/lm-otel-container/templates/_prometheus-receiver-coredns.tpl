{{/*
prometheus/coredns receiver — CoreDNS pods in kube-system.
*/}}
{{- define "lm-otel-container.prometheusReceiverCoredns" -}}
prometheus/coredns:
  config:
    scrape_configs:
      - job_name: coredns
        scrape_interval: {{ .Values.controlPlaneMonitoring.scrapeInterval }}
        kubernetes_sd_configs:
          - role: pod
            namespaces:
              names: [kube-system]
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_label_k8s_app]
            action: keep
            regex: kube-dns|coredns
          - source_labels: [__meta_kubernetes_pod_ip]
            target_label: __address__
            replacement: $1:9153
{{- end }}
