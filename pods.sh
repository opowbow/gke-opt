#!/bin/bash

get_pod_info() {
  local namespace="$1"
  # No need to check for empty namespace here, as the main loop control ensures it's set.

  # Get all node info (instance-type and spot)
  declare -A node_info_map
  while IFS=$'\t' read -r node_name instance_type spot_label; do
    is_spot="false"
    if [[ "$spot_label" == "true" ]]; then
      is_spot="true"
    fi
    node_info_map["$node_name"]="$instance_type	$is_spot"
  done < <(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.node\.kubernetes\.io/instance-type}{"\t"}{.metadata.labels.cloud\.google\.com/gke-spot}{"\n"}{end}')

  # Get pods, filter for 'Running' status, and format the output, for the given namespace
  kubectl get pods --namespace "$namespace" --field-selector status.phase=Running -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\n"}{end}' |
  while IFS=$'\t' read -r pod_name node_name;
 do
    # Get the instance type and spot status from the map
    node_info="${node_info_map[$node_name]}"
    IFS=$'\t' read -r instance_type is_spot <<< "$node_info"

    instance_type_output="$instance_type"
    if [[ "$is_spot" == "true" ]]; then
      instance_type_output+=" (spot)"
    fi

    # Print the pod name, instance type, and namespace
    printf "% -40s % -30s %s\n" "$pod_name" "$instance_type_output" "$namespace"
  done
}

compare_and_print() {
  local current_output="$1"
  local previous_output="$2"

  if [[ -z "$previous_output" ]]; then
    echo "$current_output"
    return 0
  fi

  local current_lines
  readarray -t current_lines < <(echo "$current_output")
  local previous_lines
  readarray -t previous_lines < <(echo "$previous_output")

  local new_lines=()

  for line in "${current_lines[@]}"; do
    local found=0
    for prev_line in "${previous_lines[@]}"; do
      if [[ "$line" == "$prev_line" ]]; then
        found=1
        break
      fi
    done
    if [[ "$found" -eq 0 ]]; then
      new_lines+=("$line")
    fi
  done

  if [[ "${#new_lines[@]}" -gt 0 ]]; then
    printf "%s\n" "${new_lines[@]}"
  fi
}

# Set namespaces array
declare -a namespaces
if [[ "$#" -eq 0 ]]; then
  echo "No namespace provided, using 'default'."
  namespaces=("default")
else
  namespaces=("$@")
fi

# Initial previous output
previous_output=""

# Trap Ctrl+C to exit gracefully
trap 'echo "Stopping..."; exit 0' INT

echo "Monitoring namespaces: ${namespaces[*]}"
echo "---------------------------------------------------------------------------------"
printf "% -40s % -30s %s\n" "POD NAME" "NODE TYPE" "NAMESPACE"
echo "---------------------------------------------------------------------------------"

while true; do
  # Initialize current output
  current_output=""

  # Loop through each namespace
  for namespace in "${namespaces[@]}"; do
    # Get current pod info for the current namespace
    namespace_output=$(get_pod_info "$namespace")

    # Check if get_pod_info returned an error (e.g., namespace doesn't exist)
    if [[ $? -ne 0 ]]; then
      # Non-fatal error, just warn and continue with other namespaces
      echo "Warning: Could not get pod info for namespace: $namespace." >&2
      continue
    fi

    # Append the namespace output to the total current output
    if [[ -n "$namespace_output" ]]; then
      current_output+="$namespace_output"$' '
    fi
  done

  # Trim trailing newline if any
  current_output=$(echo "$current_output" | sed '/^$/d')

  # Compare with previous output and print only new lines
  compare_and_print "$current_output" "$previous_output"

  # Update previous output for the next iteration
  previous_output="$current_output"

  # Sleep for a few seconds to avoid excessive CPU usage
  sleep 5
done
