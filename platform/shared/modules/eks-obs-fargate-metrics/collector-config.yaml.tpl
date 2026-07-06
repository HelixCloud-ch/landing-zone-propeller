receivers:
  prometheus:
    config:
      global:
        scrape_interval: 60s
      scrape_configs:
        - job_name: "kubernetes-pod-resources"
          scheme: https
          tls_config:
            ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
            insecure_skip_verify: true
          bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
          kubernetes_sd_configs:
            - role: node
          relabel_configs:
            - action: labelmap
              regex: __meta_kubernetes_node_label_(.+)
            - source_labels: [__address__]
              action: replace
              target_label: __address__
              regex: '([^:]+)(?::\d+)?'
              replacement: '$1:10250'
            - source_labels: [__meta_kubernetes_node_label_eks_amazonaws_com_compute_type]
              action: keep
              regex: fargate
          metrics_path: /metrics/cadvisor

processors:
  filter:
    metrics:
      include:
        match_type: regexp
        metric_names:
          - container_cpu_usage_seconds_total
          - container_memory_working_set_bytes
          - container_network_receive_bytes_total
          - container_network_transmit_bytes_total
          - container_spec_cpu_quota
          - container_spec_memory_limit_bytes
  metricstransform:
    transforms:
      - include: container_cpu_usage_seconds_total
        match_type: strict
        action: update
        new_name: pod_cpu_usage_total
      - include: container_memory_working_set_bytes
        match_type: strict
        action: update
        new_name: pod_memory_working_set
      - include: container_network_receive_bytes_total
        match_type: strict
        action: update
        new_name: pod_network_rx_bytes
      - include: container_network_transmit_bytes_total
        match_type: strict
        action: update
        new_name: pod_network_tx_bytes
      - include: container_spec_cpu_quota
        match_type: strict
        action: update
        new_name: pod_cpu_limit
      - include: container_spec_memory_limit_bytes
        match_type: strict
        action: update
        new_name: pod_memory_limit
  cumulativetodelta:
    include:
      match_type: strict
      metrics:
        - pod_cpu_usage_total
        - pod_network_rx_bytes
        - pod_network_tx_bytes
  deltatorate:
    metrics:
      - pod_cpu_usage_total
      - pod_network_rx_bytes
      - pod_network_tx_bytes
  metricsgeneration:
    rules:
      - name: pod_cpu_utilization_over_pod_limit
        type: calculate
        metric1: pod_cpu_usage_total
        metric2: pod_cpu_limit
        operation: percent
      - name: pod_memory_utilization_over_pod_limit
        type: calculate
        metric1: pod_memory_working_set
        metric2: pod_memory_limit
        operation: percent
  batch: {}

exporters:
  awsemf:
    region: ${region}
    log_group_name: /aws/containerinsights/${cluster_name}/performance
    log_stream_name: fargate
    namespace: ContainerInsights
    dimension_rollup_option: NoDimensionRollup
    metric_declarations:
      - dimensions:
          - [ClusterName, LaunchType]
          - [ClusterName, Namespace, LaunchType]
          - [ClusterName, Namespace, PodName, LaunchType]
        metric_name_selectors:
          - pod_cpu_utilization_over_pod_limit
          - pod_cpu_usage_total
          - pod_cpu_limit
          - pod_memory_utilization_over_pod_limit
          - pod_memory_working_set
          - pod_memory_limit
          - pod_network_rx_bytes
          - pod_network_tx_bytes

service:
  pipelines:
    metrics:
      receivers: [prometheus]
      processors: [filter, metricstransform, cumulativetodelta, deltatorate, metricsgeneration, batch]
      exporters: [awsemf]
