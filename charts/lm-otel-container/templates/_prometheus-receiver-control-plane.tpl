{{/*
prometheus/control-plane receiver — apiserver, scheduler, controller-manager, etcd.
*/}}
{{- define "lm-otel-container.prometheusReceiverControlPlane" -}}
{{- $cp := .Values.controlPlaneMonitoring -}}
{{- $interval := $cp.scrapeInterval -}}
prometheus/control-plane:
  config:
    scrape_configs:
{{- if $cp.components.controlPlane.apiserver }}
      - job_name: control-plane-apiserver
        scrape_interval: {{ $interval }}
        kubernetes_sd_configs:
          - role: endpoints
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          insecure_skip_verify: true
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
          - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
            action: keep
            regex: default;kubernetes;https
{{- end }}
{{- if $cp.components.controlPlane.scheduler }}
      - job_name: control-plane-scheduler
        scrape_interval: {{ $interval }}
        kubernetes_sd_configs:
          - role: pod
            namespaces:
              names: [kube-system]
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          insecure_skip_verify: true
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_label_component]
            action: keep
            regex: kube-scheduler
          - source_labels: [__address__]
            action: replace
            regex: ([^:]+)(?::\d+)?
            replacement: $1:10259
            target_label: __address__
{{- end }}
{{- if $cp.components.controlPlane.controllerManager }}
      - job_name: control-plane-controller-manager
        scrape_interval: {{ $interval }}
        kubernetes_sd_configs:
          - role: pod
            namespaces:
              names: [kube-system]
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          insecure_skip_verify: true
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_label_component]
            action: keep
            regex: kube-controller-manager
          - source_labels: [__address__]
            action: replace
            regex: ([^:]+)(?::\d+)?
            replacement: $1:10257
            target_label: __address__
{{- end }}
{{- if $cp.components.controlPlane.etcd }}
      - job_name: control-plane-etcd
        scrape_interval: {{ $interval }}
        kubernetes_sd_configs:
          - role: pod
            namespaces:
              names: [kube-system]
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_label_component]
            action: keep
            regex: etcd
          - source_labels: [__address__]
            action: replace
            regex: ([^:]+)(?::\d+)?
            replacement: $1:2381
            target_label: __address__
{{- end }}
{{- end }}
