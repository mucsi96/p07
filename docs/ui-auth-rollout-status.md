# UI rollout — 30 October 2026

## v-101 module rollout

All 23 module references and 22 downloaded remote modules pin **v-101**.
The requested `scripts/create.sh` completed: **0 added, 1 changed, 21 destroyed**.
The update rotates the Netcup token; deletions remove seven obsolete Docker Hub
tokens and 14 Actions secrets. Their removal was verified in Terraform state and
all seven app repositories. The unused Docker provider lock entry was removed.

All 10 PVC identities/volumes and all Helm release revisions were preserved.
The post-apply plan contains only expected Netcup refresh-token rotation.
Repository-only inventory is prepared separately in p07 #62 and was not applied
in this rollout.

Monitoring identified an earlier chart-upgrade issue: operator v0.75.0 needs
the `VTAgent` CRD, but Helm's plain CRD installation does not add it on upgrade.
The operator was restarting after its cache-sync timeout despite briefly passing
readiness. The user approved installing just the missing CRD from the deployed
VictoriaMetrics stack chart **0.97.0**. All 26 chart CRDs are now established.
The operator recovered and remained ready for five minutes with no further
restarts, beyond its previous cache-sync failure interval. Final verification:
all 33 Deployments and both DaemonSets ready, all 10 PVCs preserved and Bound,
expected chart versions, accepted routes, document/API responses 302/401,
and same-origin Faro delivery 202 on all three apps.
Future stack upgrades must check and reconcile the chart's CRDs as well as
workload readiness.

## Previous v-99 static-client rollout

All 23 module source references and 22 downloaded remote modules use published
**v-99**. The user requested `scripts/create.sh`; after the three app pipelines
deployed successfully, the reviewed script completed: **0 added, 9 changed,
6 destroyed**. Deletions were only obsolete runtime-config secrets and their
read grants. No resource replacement, server reinstall or data-storage changes.

Verified live:

- All 33 Deployments and both DaemonSets ready at their observed generations.
- All 10 PVC identities and bound volumes preserved.
- All HTTPRoutes accepted with resolved references; no app body-rewrite middleware.
- All three app documents redirect signed-out users (302); unauthenticated APIs
  return 401. Blob JavaScript has exact app-origin CORS; documents have no config marker.
- Same-origin Faro accepts telemetry from all three apps (202).
- Static client **5.0.0** on all three apps; Spring **37.0.0**, Go **8.0.0**,
  Rust **7.0.0**, ForwardAuth **8.0.0**.
- Platform: workload identity **1.6.1**, Prometheus CRDs **32.0.2**, VictoriaMetrics
  stack **0.97.0**, oauth2-proxy **10.7.1**, Alloy/Faro **1.15.0**, PostgreSQL
  chart **17.0.0**, Redis chart **3.0.0**.

A fresh post-apply plan contains only expected Netcup refresh-token rotation;
no application or platform resource changes remain. That plan was not applied.

Earlier rollout checkpoints remain in Git history. Architecture and diffs:
[Skeleton #105](https://github.com/mucsi96/skeleton-app/issues/105).
