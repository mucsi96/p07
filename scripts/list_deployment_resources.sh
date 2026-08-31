#!/bin/bash
# Lists every deployment's and statefulset's containers with their four
# resource settings (CPU/memory request and limit) next to the live usage
# reported by metrics-server, as JSON. The output is meant to be pasted into
# an LLM to decide which requests/limits need tuning. CPU values are
# millicores, memory values are Mi; null means not set / no metrics data.
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
kubectl get statefulsets --all-namespaces -o json > "$workdir/statefulsets.json"
kubectl get replicasets --all-namespaces -o json > "$workdir/replicasets.json"
kubectl get pods --all-namespaces -o json > "$workdir/pods.json"

# Live usage; tolerate a missing metrics-server so the limits are still listed.
if ! kubectl top pod --all-namespaces --containers --no-headers > "$workdir/top.txt" 2> "$workdir/top.err"; then
  echo "warning: 'kubectl top pod' failed - usage values will be null (is metrics-server enabled?)" >&2
  cat "$workdir/top.err" >&2
  : > "$workdir/top.txt"
fi

jq -n \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --slurpfile deployments "$workdir/deployments.json" \
  --slurpfile statefulsets "$workdir/statefulsets.json" \
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

  def round_or_null: if . == null then null else round end;

  # namespace/replicaset -> owning deployment name
  ($replicasets[0].items
   | map({ key: "\(.metadata.namespace)/\(.metadata.name)",
           value: ((.metadata.ownerReferences // []) | map(select(.kind == "Deployment")) | .[0].name) })
   | from_entries) as $rs_owner

  # namespace/pod -> owning workload ("Deployment/name" via its replicaset,
  # or "StatefulSet/name" directly)
  | ($pods[0].items
     | map((.metadata.ownerReferences // [])[0] as $owner
           | { key: "\(.metadata.namespace)/\(.metadata.name)",
               value: (if $owner.kind == "ReplicaSet" then
                         ($rs_owner["\(.metadata.namespace)/\($owner.name)"] as $dep
                          | if $dep != null then "Deployment/\($dep)" else null end)
                       elif $owner.kind == "StatefulSet" then "StatefulSet/\($owner.name)"
                       else null end) })
     | map(select(.value != null))
     | from_entries) as $pod_owner

  # namespace/kind/workload/container -> usage summed across pods
  | ($top
     | split("\n")
     | map(select(test("\\S")) | [splits("\\s+")] | select(length >= 5))
     | map({ ns: .[0], pod: .[1], container: .[2], cpu: (.[3] | cpu_m), mem: (.[4] | mem_mi) })
     | map(. + { owner: $pod_owner["\(.ns)/\(.pod)"] })
     | map(select(.owner != null))
     | group_by("\(.ns)/\(.owner)/\(.container)")
     | map({ key: "\(.[0].ns)/\(.[0].owner)/\(.[0].container)",
             value: { cpu: (map(.cpu) | add), mem: (map(.mem) | add) } })
     | from_entries) as $usage

  | def workload(kind):
      .metadata.namespace as $ns
      | .metadata.name as $name
      | {
          kind: kind,
          namespace: $ns,
          name: $name,
          replicas: { desired: (.spec.replicas // 0), ready: (.status.readyReplicas // 0) },
          containers: [
            .spec.template.spec.containers[]
            | ($usage["\($ns)/\(kind)/\($name)/\(.name)"] // {}) as $u
            | {
                name: .name,
                cpu: {
                  request: (.resources.requests.cpu // null | cpu_m | round_or_null),
                  limit:   (.resources.limits.cpu   // null | cpu_m | round_or_null),
                  usage:   ($u.cpu | round_or_null)
                },
                memory: {
                  request: (.resources.requests.memory // null | mem_mi | round_or_null),
                  limit:   (.resources.limits.memory   // null | mem_mi | round_or_null),
                  usage:   ($u.mem | round_or_null)
                }
              }
          ]
        };

  {
      generatedAt: $generated_at,
      units: { cpu: "millicores", memory: "Mi" },
      note: "usage is live metrics-server data summed across the workload'\''s running pods; null = not set / no data",
      workloads: ([ ($deployments[0].items[]  | workload("Deployment")),
                    ($statefulsets[0].items[] | workload("StatefulSet")) ]
                  | sort_by([.namespace, .name]))
    }
'
