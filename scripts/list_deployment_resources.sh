#!/bin/bash
# Lists every deployment's containers with their four resource settings
# (CPU/memory request and limit) next to the live usage reported by
# metrics-server. The output is meant to be pasted into an LLM (or read by a
# human) to decide which requests/limits need tuning.
set -euo pipefail

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required but not found in PATH" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not found in PATH" >&2
  exit 1
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

kubectl get deployments --all-namespaces -o json > "$workdir/deployments.json"
kubectl get replicasets --all-namespaces -o json > "$workdir/replicasets.json"
kubectl get pods --all-namespaces -o json > "$workdir/pods.json"

# Live usage; tolerate a missing metrics-server so the limits are still listed.
if ! kubectl top pod --all-namespaces --containers --no-headers > "$workdir/top.txt" 2> "$workdir/top.err"; then
  echo "warning: 'kubectl top pod' failed - usage columns will be empty (is metrics-server enabled?)" >&2
  cat "$workdir/top.err" >&2
  : > "$workdir/top.txt"
fi

echo "# Deployment resource requests/limits vs live usage ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
echo "# CPU_USAGE/MEM_USAGE are summed across the deployment's running pods; '-' means not set / no data."

jq -rn \
  --slurpfile deployments "$workdir/deployments.json" \
  --slurpfile replicasets "$workdir/replicasets.json" \
  --slurpfile pods "$workdir/pods.json" \
  --rawfile top "$workdir/top.txt" '
  # Normalize a CPU quantity ("250m", "0.5", "1") to millicores.
  def cpu_m:
    if . == null then null
    elif test("^[0-9.]+m$") then (rtrimstr("m") | tonumber)
    elif test("^[0-9.]+$") then (tonumber * 1000)
    else null end;

  # Normalize a memory quantity to Mi.
  def mem_mi:
    if . == null then null
    elif test("^[0-9.]+Ki$") then ((rtrimstr("Ki") | tonumber) / 1024)
    elif test("^[0-9.]+Mi$") then (rtrimstr("Mi") | tonumber)
    elif test("^[0-9.]+Gi$") then ((rtrimstr("Gi") | tonumber) * 1024)
    elif test("^[0-9.]+Ti$") then ((rtrimstr("Ti") | tonumber) * 1024 * 1024)
    elif test("^[0-9.]+k$")  then ((rtrimstr("k")  | tonumber) * 1000 / 1048576)
    elif test("^[0-9.]+M$")  then ((rtrimstr("M")  | tonumber) * 1000000 / 1048576)
    elif test("^[0-9.]+G$")  then ((rtrimstr("G")  | tonumber) * 1000000000 / 1048576)
    elif test("^[0-9.]+$")   then (tonumber / 1048576)
    else null end;

  def fmt_cpu: if . == null then "-" else "\(round)m" end;
  def fmt_mem: if . == null then "-" else "\(round)Mi" end;

  # namespace/replicaset -> owning deployment name
  ($replicasets[0].items
   | map({ key: "\(.metadata.namespace)/\(.metadata.name)",
           value: ((.metadata.ownerReferences // []) | map(select(.kind == "Deployment")) | .[0].name) })
   | from_entries) as $rs_owner

  # namespace/pod -> owning deployment name
  | ($pods[0].items
     | map(((.metadata.ownerReferences // []) | map(select(.kind == "ReplicaSet")) | .[0].name) as $rs
           | select($rs != null)
           | { key: "\(.metadata.namespace)/\(.metadata.name)",
               value: $rs_owner["\(.metadata.namespace)/\($rs)"] })
     | map(select(.value != null))
     | from_entries) as $pod_owner

  # namespace/deployment/container -> usage summed across pods
  | ($top
     | split("\n")
     | map(select(test("\\S")) | [splits("\\s+")] | select(length >= 5))
     | map({ ns: .[0], pod: .[1], container: .[2], cpu: (.[3] | cpu_m), mem: (.[4] | mem_mi) })
     | map(. + { dep: $pod_owner["\(.ns)/\(.pod)"] })
     | map(select(.dep != null))
     | group_by("\(.ns)/\(.dep)/\(.container)")
     | map({ key: "\(.[0].ns)/\(.[0].dep)/\(.[0].container)",
             value: { cpu: (map(.cpu) | add), mem: (map(.mem) | add) } })
     | from_entries) as $usage

  | ["NAMESPACE", "DEPLOYMENT", "CONTAINER", "READY",
     "CPU_REQUEST", "CPU_LIMIT", "CPU_USAGE",
     "MEM_REQUEST", "MEM_LIMIT", "MEM_USAGE"],
    ($deployments[0].items[]
     | .metadata.namespace as $ns
     | .metadata.name as $dep
     | "\(.status.readyReplicas // 0)/\(.spec.replicas // 0)" as $ready
     | .spec.template.spec.containers[]
     | ($usage["\($ns)/\($dep)/\(.name)"] // {}) as $u
     | [ $ns, $dep, .name, $ready,
         (.resources.requests.cpu    // null | cpu_m  | fmt_cpu),
         (.resources.limits.cpu      // null | cpu_m  | fmt_cpu),
         ($u.cpu | fmt_cpu),
         (.resources.requests.memory // null | mem_mi | fmt_mem),
         (.resources.limits.memory   // null | mem_mi | fmt_mem),
         ($u.mem | fmt_mem) ])
  | @tsv
' | awk -F'\t' '
  { for (i = 1; i <= NF; i++) { if (length($i) > w[i]) w[i] = length($i); cell[NR, i] = $i } nf[NR] = NF }
  END {
    for (r = 1; r <= NR; r++)
      for (i = 1; i <= nf[r]; i++)
        printf "%-*s%s", (i == nf[r] ? length(cell[r, i]) : w[i] + 2), cell[r, i], (i == nf[r] ? "\n" : "")
  }'
