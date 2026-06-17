#!/bin/bash

# Print the header
printf "%-65s %-8s %-30s %s\n" "Node Name" "Spot" "Machine Type" "Accelerator"
printf -- "-%.0s" {1..65}
printf " %-8s %-30s %s\n" "----" "------------" "-----------"

# Get node name, provisioning label, and instance type label
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.creationTimestamp}{"\t"}{.metadata.name}{"\t"}{.metadata.labels.cloud\.google\.com/gke-provisioning}{"\t"}{.metadata.labels.node\.kubernetes\.io/instance-type}{"\t"}{.metadata.labels.cloud\.google\.com/gke-tpu-accelerator}{"\t"}{.metadata.labels.cloud\.google\.com/gke-accelerator}{"\n"}{end}' | \
sort -r | \
while IFS=$'\t' read -r _ node_name provisioning_label machine_type tpu_accelerator gpu_accelerator; do
  is_spot="false"
  if [ "$provisioning_label" == "spot" ]; then
    is_spot="true"
  fi

  if [ -z "$machine_type" ]; then
    machine_type="<unknown>"
  fi

  accelerator="<none>"
  if [ -n "$tpu_accelerator" ]; then
    accelerator="$tpu_accelerator"
  elif [ -n "$gpu_accelerator" ]; then
    accelerator="$gpu_accelerator"
  fi

  printf "%-65s %-8s %-30s %s\n" "$node_name" "$is_spot" "$machine_type" "$accelerator"
done
