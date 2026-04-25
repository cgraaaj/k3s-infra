# Infrastructure Upgrade Roadmap

Living document tracking the **current pin → next safe step → final target** for every
Helm chart under `argo-registry/qa/manifests/infra/`. Update this as each step is
merged so the next engineer knows what's in-flight.

## Upgrade tier definitions

| Tier | Meaning | Trigger |
|------|---------|---------|
| **T1** | Same-minor patch (e.g. `1.8.1 → 1.8.2`, `v1.17.1 → v1.17.4`) | Renovate auto-merges |
| **T2** | One-minor bump, same-major chart (e.g. `0.30.1 → 0.32.0`) | Renovate dashboard checkbox |
| **T3** | Multi-minor / major / year-boundary / N-2 rule chart | Manual migration with runbook |

## Current status (post this change)

| Chart | Pin | Latest stable | Last step | Remaining |
|-------|-----|---------------|-----------|-----------|
| argocd-image-updater          | `1.1.5`       | `1.1.5`        | — | none |
| kubernetes-replicator         | `2.12.3`      | `2.12.3`       | — | none |
| loki-stack                    | `2.10.3`      | `2.10.3`       | — | none |
| minio                         | `5.4.0`       | `5.4.0`        | — | none |
| **vault** (hashicorpvault)    | `0.32.0` ⬆ from `0.30.1` | `0.32.0` | T2 | — (StatefulSet image rolls when pod is recycled; auto-unseal CronJob now hardened, see below) |
| **cert-manager**              | `v1.20.2` ⬆ from `v1.19.5` (2026-04-24, CRDs reconciled v1.12.10 → v1.20.2) | `v1.20.2` | T3-step-3 | — (caught up to latest) |
| **istio-base / istiod / gateway** | `1.27.9` ⬆ from `1.25.5` (2026-04-24, N-2 skip 1.26) | `1.29.2` | T3-step-2 (N-2 skip) | `1.29.x` — gated on sidecar convergence |
| **longhorn**                  | `1.11.1` ⬆ from `1.10.2` (2026-04-24, snapshots `pre-111-20260424-1244-*` taken) | `1.11.1` | T3-step-3 | — (caught up to latest) |
| **authentik**                 | `2025.12.4` ⬆ from `2025.2.4` (PG15→17 + local-path→longhorn-retain done 2026-04-24) | `2026.2.2` | T3-step-1 | `2025.12.4` → `2026.2.2` (year-release, see runbook) |
| **traefik**                   | `38.0.2` ⬆ from `37.4.0` (2026-04-24, runtime v3.6.2 → v3.6.6) | `39.0.8` | T3-step-3 | `38.x` → `39.x` (T2 once soak ends ~2026-04-29) |
| **kube-prometheus-stack**     | `75.15.2`     | `84.0.0`       | — | T3 — defer, CRD migration needed |
| **kiali-server**              | `1.89.0`      | `2.25.0`       | — | T3 — v1→v2 full rewrite, defer |
| **gitlab-runner**             | `0.68.1`      | `0.88.1`       | — | T3 — GitLab Runner 17→18, defer |

### Verification snapshot — 2026-04-26

Pulled live from the `dev` k3s cluster (the QA target):

- **Helm pin parity** — all 17 `targetRevision` values in `argo-registry/qa/manifests/infra/*.yaml` match the table above; no drift between Git and the rendered Applications.
- **Argo Application health** — all `infra/` apps are `Synced/Healthy` except:
  - `longhorn` `OutOfSync` — expected, the `Service/longhorn-conversion-webhook` orphan documented under "Known benign drift after 1.10".
  - `prometheus` `OutOfSync` — chart not bumped yet (75.15.2 still in Git, see T3 row).
- **Vault** — `Sealed=false`, runtime `1.20.1`, `vault-unseal` CronJob completing successfully in-cluster.
- **Istio data-plane** — `istiod` at `pilot:1.27.9`; sidecars: 7 at `proxyv2:1.27.9`, **2 still at `proxyv2:1.23.2`** (both in `stockx/stockx-svc-stockx-svc-k8s-fffc66778-*`). See "Open blockers" below.
- **`vault-unseal` CronJob Git tracking** — file exists in Git but no Argo `Application` references it; the in-cluster object is still labelled `app.kubernetes.io/managed-by: kubectl`. See "Open blockers" below.

## Open blockers (clear these before any T3 motion)

### B1. `stockx-svc` CrashLoop is gating Istio sidecar convergence

`Deployment/stockx-svc-stockx-svc-k8s` in namespace `stockx` is `0/2` Available. All three
pods are in `CrashLoopBackOff` — the app container `stockx-svc-k8s` (image
`registry.cgraaaj.in/stock-x/stockx-svc:2.7`) returns HTTP 500 on its readiness probe and
fails its liveness probe. The rolling-restart we issued on 2026-04-24 to swap sidecars
from 1.23.2 → 1.27.9 created a new ReplicaSet (`65b6fdd9f8`) whose pod can never go
Ready, so the rolling update keeps both old `fffc66778`-RS pods alive (still on
`proxyv2:1.23.2`) to maintain — paradoxically — *zero* availability.

Until this is resolved we cannot proceed to Istio 1.29 (would put istiod at N-6 from the
data-plane = mesh-breaking).

Options, in increasing order of safety:

1. **Quick / risky** — `kubectl -n stockx scale deploy/stockx-svc-stockx-svc-k8s --replicas=0`
   then back to `2`. Frees the stale 1.23.2 sidecars immediately; workload stays offline
   (it already is).
2. **Correct** — fix the underlying `stockx-svc-k8s` 500. Likely a missing dependency
   (DB / upstream API / config). Owner: stockx app team. Tracking it here only because
   it gates the infra upgrade train.
3. **Enterprise / structural** — give every long-lived `Deployment` a
   `PodDisruptionBudget` AND a non-zero `progressDeadlineSeconds`, plus an Argo
   `Application` health-check that surfaces stuck rollouts. We currently rely on
   "someone notices the Argo dashboard says Degraded", which is what let this sidecar
   skew develop.

### B2. `vault-unseal` CronJob is not in the GitOps loop

`hashicorpvault/vault-unseal-cronjob.yaml` is committed but no Argo `Application`
references it, so:

- It is invisible to `bootstrap-qa` (which globs `argo-registry/qa/manifests/**/*.yaml`).
- The in-cluster object still has `app.kubernetes.io/managed-by: kubectl` — i.e. any
  drift in the file will not propagate, and an accidental `kubectl delete` would not
  self-heal.

Two fixes:

1. **Direct (quick)** — add a tiny Argo `Application` at
   `argo-registry/qa/manifests/infra/vault-unseal.yaml` with
   `source.repoURL: https://github.com/cgraaaj/k3s-infra.git`, `path: hashicorpvault/`,
   `destination.namespace: hashicorpvault`. `bootstrap-qa` will pick it up on the next
   poll. Pros: zero churn on the existing `hashicorpvault` Application. Cons: two
   Applications now own resources in the same namespace; sync ordering between the
   chart and the CronJob has to be expressed via sync-waves (give the CronJob `wave: 5`
   so it lands after the StatefulSet).
2. **Enterprise / best-practice** — convert `hashicorpvault.yaml` to a **multi-source
   Application** (Argo CD ≥ 2.6, `spec.sources: [...]`): source 1 = the upstream Helm
   chart (unchanged), source 2 = `repoURL=k3s-infra`, `path=hashicorpvault/`,
   `directory.recurse=true`. Pros: one logical Application owns *everything* Vault-
   related (chart, CronJob, future companion CRs like sealed `vault-unseal-keys` once
   it moves into Git, audit-log shipping configs, etc.); avoids cross-Application sync
   coordination; one place to flip `prune`/`selfHeal`/`automated`. Cons: requires a
   one-time Argo CD `Application` recreate (Argo can't switch a single-source app to
   multi-source live; delete + re-apply with the finalizer skipped to preserve
   resources).

Recommendation: take option (2). The follow-up was already flagged in the
`vault-unseal CronJob` section below, and a multi-source layout is the right long-term
home for "chart + companion manifests" patterns we'll re-encounter (e.g. authentik
outpost overlays, longhorn `RecurringJob` CRs).

## What's next — priority queue

| # | Tier | Action | Gate / pre-condition |
|---|------|--------|----------------------|
| 1 | n/a  | **B1** — unblock stockx-svc OR scale to 0 to release stale 1.23.2 sidecars | none — do this first |
| 2 | n/a  | **B2** — wire `vault-unseal` CronJob into Argo (multi-source `hashicorpvault` app preferred) | none — independent of (1) |
| 3 | T2   | Traefik `38.0.2` → `39.x`                                                   | soak ends ≈ 2026-04-29; re-diff `helm template` because chart 39 likely tightens more `additionalProperties:false` schemas |
| 4 | T3   | Istio `1.27.9` → `1.29.2` (base/istiod/gateway lockstep, gateway last)      | (1) cleared AND `istioctl x precheck` clean |
| 5 | T3   | Authentik `2025.12.4` → `2026.2.x`                                          | take Longhorn snapshot of `data-authentik-postgresql-0` first |
| 6 | T3   | kube-prometheus-stack `75.15.2` → `84.0.0`, staged 75→80→82→84              | CRD diff per step; verify `up{}` after each |
| 7 | T3   | kiali-server `1.89.0` → `2.x` (re-authored values)                          | best done after (6); kiali 2 expects newer prom-operator CRDs |
| 8 | T3   | gitlab-runner `0.68.1` → `0.88.1`, via `0.80.x`                             | review GitLab Runner 18.0 / 18.6 release notes |

## Runbooks for remaining T3 migrations

### Istio 1.25 → 1.27 → 1.29 (N-2 rule) — **step-2 done; 1.29 deferred (sidecar gate)**
Istio supports skipping at most 2 minor versions. Sequence:

1. ~~Merge initial PR and confirm 1.25.5 is Healthy~~ ✅ done.
2. ~~Wait ≥ 1 week on 1.25 in dev before the next step~~ — soak shortened to <1d in dev.
3. ~~Bump all three (`base`, `istiod`, `gateway`) to `1.27.9` in one commit. Gateway last.~~ ✅ done 2026-04-24, all three Synced/Healthy, CRDs at 1.27.9, smoke-tests `auth.dev`/`mediaradar`/`grafana.dev`/`kiali.dev` returned HTTP 302.
4. **Sidecar convergence (gating step for 1.29)** — STARTED 2026-04-24, **STILL OPEN as
   of 2026-04-26**. Discovered that existing app sidecars were at `proxyv2:1.23.2`
   (already N-4 from istiod 1.27.9 — outside the supported skew, only working because
   xDS is forward-tolerant). Initiated `kubectl rollout restart deployment` on all 5
   injected workloads (`mediaradar/mediaradar-mr-k8s`, `mediaradar-svc/mediaradar-svc-k8s`,
   `optionscope/optionscope-optionscope-k8s`, `stockx/stockx-svc-stockx-svc-k8s`,
   `tickerflow/tickerflow-k8s`). New pods inject sidecars at `proxyv2:1.27.9`; old pods
   continue serving until new are Ready. The `mediaradar-mr-k8s` Deployment had
   `replicas:1` with `maxUnavailable:25%` (rounded down to 0) so the rollout deadlocked
   until the old pod was deleted manually — note for future restarts. Initial blockage
   was slow `vault-agent-init` waiting on a sealed Vault (now resolved, Vault unsealed).
   **Residual as of 2026-04-26**: cluster still has `7 × proxyv2:1.27.9` and
   `2 × proxyv2:1.23.2`. Both stale sidecars are in
   `stockx/stockx-svc-stockx-svc-k8s-fffc66778-{g6ls7,qkznz}` (old ReplicaSet kept alive
   because the new RS pod cannot pass readiness — the app container 500s; see "Open
   blockers / B1"). Until ALL sidecars are at 1.27.9, do **not** step istiod to 1.29
   (would put istiod at N-6 from data-plane = mesh-breaking).
5. Bump to `1.29.2` once `kubectl get pods -A -o jsonpath='...istio-proxy...'` shows zero
   1.23.2 sidecars. Same lockstep (base/istiod/gateway, gateway last) + same soak.

**Pre-flight before each step**: `istioctl x precheck` from a pod with `istioctl` installed.

### cert-manager 1.18 → 1.19 → 1.20 — **step-3 done 2026-04-24, caught up**
cert-manager supports N+1 minor bumps directly, but each bump may add/deprecate CRD fields.

1. ~~Confirm 1.18.6 Healthy.~~ ✅ done.
2. ~~Fix the pre-existing CRD drift~~ ✅ done 2026-04-24. Important learning: **`helm.skipCrds`
   is a no-op for cert-manager ≥1.18** because the chart no longer ships CRDs in the legacy
   `crds/` folder; they are gated behind a value `crds.enabled` (default `false`). The fix
   was to set both `crds.enabled: true` and `crds.keep: true` via inline `helm.parameters`
   in `cert-manager.yaml`. CRDs jumped from v1.12.10 → v1.20.2, all six now
   `app.kubernetes.io/managed-by: Helm` with `helm.sh/resource-policy: keep` (so an
   accidental uninstall never cascade-deletes Issuer/Certificate CRs). Pre-existing 17
   Certificates and 2 ClusterIssuers stayed `Ready=True` throughout the swap.
3. ~~Bump chart to `v1.19.5`~~ ✅ done 2026-04-24-step2 (required `Replace=true` once for the
   `$retainKeys` SSA issue + delete the immutable `startupapicheck` Job).
4. ~~Bump chart to `v1.20.2`~~ ✅ done 2026-04-24-step3, in the same sync as the CRD flip.
   Same `Replace=true` syncOptions used (the chart still uses `$retainKeys` in
   `Deployment.spec.strategy`). Cleanup: deleted orphaned RoleBinding
   `cert-manager-cert-manager-tokenrequest` left behind from chart 1.18.6 (renamed to
   `cert-manager-tokenrequest` in 1.19+) and post-install `startupapicheck` hook resources.
   App is `Synced/Healthy`.

### longhorn 1.9 → 1.10 → 1.11 — **step-3 done 2026-04-24, caught up**
**Storage — never skip minors**. Each bump requires:

1. Take a [Longhorn backup snapshot](https://longhorn.io/docs/1.11.1/snapshots-and-backups/)
   of every PV first. ✅ For 1.10.2: snapshots `pre-110-20260424-1118-*` exist on all
   7 attached volumes (authentik PG, vault data + audit, grafana, loki, both minio shards),
   each `readyToUse: true`. Repeat this step before 1.11.x.
2. Confirm no volume is in `Detached` or `Degraded` state before the bump. (jenkins/jenkins
   PVC is permanently `Detached/unknown` — ignored as the workload is archived.)
3. Bump chart one minor. ✅ 1.9.2 → 1.10.2 done 2026-04-24.
4. Watch `longhorn-manager` pods roll, then `engine-image-*` DaemonSet re-roll. ✅
   manager DS rolled across all 5 nodes; new engine-image v1.10.2 deploying (3/5 nodes
   healthy, 2 RPi nodes — invoker/juggernaut — slow on intermittent DNS to
   `production.cloudflare.docker.com` and still pulling at the time of this commit).
   Existing volumes stay on their current engine until the next detach/attach cycle.
5. Test a volume detach/attach cycle before proceeding to 1.11.x.
6. ~~Bump 1.10.2 → 1.11.1.~~ ✅ done 2026-04-24-step3. Pre-bump snapshots
   `pre-111-20260424-1244-*` taken on all 7 attached volumes. Chart applied,
   `longhorn-post-upgrade` Helm hook completed. Post-upgrade verification:
   - all 7 stateful volumes `attached + healthy`
   - Vault stayed unsealed throughout the rolling restart of `longhorn-manager`
   - Authentik PG, mediaradar, grafana, kiali, auth.dev all returned HTTP 302/200
   - longhorn-manager DaemonSet now at `v1.11.1` (6/7 nodes; one RPi engine-image still
     pulling slowly — same node-level DNS issue as the 1.10 bump)
   - existing per-PV engine images remain at their previous version (1.8.x, 1.9.2, 1.10.2)
     until the next detach/attach; this is normal Longhorn behavior.

> **Known benign drift after 1.10:** `Service/longhorn-conversion-webhook` is
> `OutOfSync` because chart 1.10.x removed it; with `prune: false` ArgoCD correctly
> leaves the orphan in place. Either prune it manually once when convenient or keep
> it; it's not selected by any pod after upgrade. Still present after 1.11.1.

### traefik 36 → 37 → 38 → 39 — **step-3 done 2026-04-24**
Chart 36.x → 39.x stays on Traefik runtime v3.x; the values schema is largely backward
compatible across these minors but the chart restructured a few defaults per minor.

1. ~~Bump 36.3.0 → 37.4.0 (runtime v3.4.3 → v3.6.2)~~ ✅ done 2026-04-24-step2.
2. ~~Bump to 38.0.2 (runtime v3.6.6)~~ ✅ done 2026-04-24-step3. **Breaking schema
   change found**: chart 38 enforces `additionalProperties:false` on
   `ports.<entryPoint>`, so the top-level `advertisedPort: 4443` we had under
   `ports.websecure` was rejected. Re-nested it under `ports.websecure.http3:`
   (the only valid location, which is also the actual semantic intent —
   it controls `--entryPoints.websecure.http3.advertisedPort` because http3 is
   enabled). Always check the rendered helm output of the new chart against
   our values when bumping a chart major; chart 38 added many `# @schema` strict
   annotations.
3. Soak ≥ 3-5 days, watch access logs / `traefik` Service `LoadBalancer` IP.
4. Bump to 39.x latest stable.

### kube-prometheus-stack 75 → 84 (major chart bumps bundle prometheus-operator CRD updates)

CRD fields on `Prometheus`, `Alertmanager`, `ServiceMonitor`, `PodMonitor`, `ThanosRuler`
are occasionally renamed or removed. Upgrade sequence:

1. Diff `helm show crds prometheus-community/kube-prometheus-stack --version <new>` vs current.
2. Bump in 3-4 steps via the Renovate dashboard (75 → 80 → 82 → 84).
3. After each step, verify all `ServiceMonitor` and `PodMonitor` are still scraping
   (Prometheus `up{}` graph > 0 per target).

### kiali 1.89 → 2.x
Kiali 2.x is a major rewrite — the Helm values schema changed significantly (server config,
auth strategy, graph UI). **Not a drop-in replacement.**

1. Diff the chart's `values.yaml`: `helm show values kiali/kiali-server --version 2.25.0 > /tmp/kiali-2.yaml`
2. Re-author `argo-registry/qa/manifests/infra/kiali.yaml` against the new schema.
3. Deploy to a staging namespace first if possible, or keep the 1.89 Application ready for
   rollback.

### gitlab-runner 0.68 → 0.88 (GitLab Runner 17.3 → 18.11)
GitLab Runner has had multiple config file format changes between 17.x and 18.x (cache
backend, executor options, metrics). Recommended:

1. Read GitLab Runner 18.0 and 18.6 release notes.
2. Bump the chart `0.68.1 → 0.80.x` first (still Runner 18.3.x), verify jobs still execute.
3. Then step to `0.88.1`.

### authentik: PG15 → PG17 + local-path → longhorn-retain — **COMPLETED 2026-04-24** (Path B)

**Outcome (2026-04-24):** chart rolled forward `2025.2.4 → 2025.12.4`, postgres data
migrated from `bitnami/postgresql:15.8` on `local-path` (single-node, reclaim=Delete) to
`docker.io/library/postgres:17.7-bookworm` on `longhorn-retain` (replicated,
reclaim=Retain). All 207 public tables, 733 indexes, 327 FKs, 9 triggers restored
cleanly via `pg_dumpall | psql`; row counts (users, tokens, flows, sessions, providers,
applications) verified equal to source. Auth-gated routes (mediaradar, grafana, admin
UI) all returned the expected `302`/`200` codes immediately after restore.

Reference commits in this repo:
- chart bump + storageclass override (Phase 3)
- re-enable `syncPolicy.automated` (Phase 7)
- this roadmap update (Phase 8)

**Side-effect (intentional):** chart `2025.12.4` dropped the `redis` subchart entirely.
authentik now uses PostgreSQL for sessions/channels/cache (see
`django_channels_postgres` migration and `using PostgreSQL session backend` server log).
The auto-prune cleanly removed the leftover redis pod / STS / PVC / Service / CMs
during the Phase 7 sync.

#### Lessons learned (apply to future major chart bumps)

1. **Chart key restructuring**: `2025.10.x` flipped the postgres section to bitnami
   subchart layout. The correct override keys are now
   `postgresql.primary.persistence.{enabled,storageClass,size}`, NOT
   `postgresql.storageClass` / `postgresql.persistence.storageClass`. Always
   `helm show values <chart> --version <new>` before authoring `helm.parameters`
   inline overrides.
2. **`primary.persistence.enabled` defaults to false** in chart 2025.12.4 (the bitnami
   subchart's default is true, but the goauthentik chart comments out its primary
   persistence block). Without an explicit override the rendered STS would be
   emptyDir-backed.
3. **Changing `volumeClaimTemplates.spec.storageClassName` is forbidden** on an existing
   StatefulSet (immutable field). Workflow has to be: scale STS to 0 → `kubectl delete sts`
   → `argocd app sync` (with `Replace=true` if the chart also uses `$retainKeys` in
   Deployment.spec.strategy, which authentik 2025.12.4 does).
4. **Upstream `library/postgres:17` image vs bitnami entrypoint env vars**: the upstream
   image only honours `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB`. It IGNORES
   the bitnami-flavoured `POSTGRES_POSTGRES_PASSWORD_FILE` mount, so the `postgres`
   superuser ends up with NO password (initdb default). The chart-renamed `authentik`
   role IS the superuser, so use it for `psql` operations (PG15 dumps restore cleanly
   under it as long as you trim the `\connect postgres` tail).
5. **`pg_dumpall --clean --if-exists`** would `DROP ROLE authentik` and overwrite its
   password from the dump's old hash — bad, because the K8s Secret-tracked password is
   what the new server pod uses. Restore with sed-extracted lines `\connect authentik`
   .. `\connect postgres` instead, or use `pg_dump -d authentik` from the start. Don't
   feed the entire `pg_dumpall` output to `psql` against the new cluster.
6. **Auto-prune of removed subcharts is correct, but verify the app still works first.**
   Don't re-enable `automated.prune: true` until you have manually confirmed the
   service is healthy on the new chart.

#### Repeatable runbook (for future chart-driven storage-class migrations)

```
# 0. preflight: helm template the new chart with overrides, confirm STS name + PVC name + image
# 1. pg_dumpall warm dump (DB still serving) -> .backups/  (gitignored)
# 2. scale server+worker to 0  -> auth outage starts; take final consistent dump
# 3. git: bump targetRevision + add helm.parameters override + KEEP automated block OFF
# 4. scale STS to 0 → delete PVC → delete STS → argocd sync (RespectIgnoreDifferences,Replace,SSA)
# 5. drop+recreate empty DB → stream the authentik-only dump section into psql
# 6. scale server+worker back to 1 → verify outpost endpoints + smoke test 302/200
# 7. git: re-enable syncPolicy.automated → bootstrap-qa picks it up → app reconciles Synced/Healthy
# 8. update this roadmap, verify no stray PVs, final commit
```

### cert-manager v1.17 → v1.18: needs `Replace=true` sync option

The jetstack chart renders the `Deployment.spec.strategy` field with a `$retainKeys`
merge directive that trips ArgoCD's SSA (`field not declared in schema`). Solution is to
sync with `Replace=true` once (fallback to client-side apply):

```
kubectl -n argocd-qa patch applications.argoproj.io cert-manager --type merge \
  -p '{"operation":{"sync":{"syncOptions":["RespectIgnoreDifferences=true","Replace=true"]}}}'
```

Subsequent patch bumps within v1.18 don't need Replace=true again.

### vault-unseal CronJob — moved into Git + hardened (2026-04-24)

The `vault-unseal` CronJob in the `hashicorpvault` namespace was previously created
out-of-band with `kubectl apply` and had no representation in Git. During the istio
sidecar convergence work it was found that Vault had been **sealed for ~18 h**, blocking
every `vault-agent-init` container in the cluster. Root causes:

1. The original CronJob script used `set -e` *without* `-u`, returned exit-0 even when
   curl failed, and had no final verification that the seal status had actually flipped.
   Failures were therefore silent.
2. `activeDeadlineSeconds: 45` was too short for the slower RPi nodes to pull
   `curlimages/curl:latest` cold, so half the runs were `DeadlineExceeded`.
3. The image was unpinned (`:latest`), so a sudden DockerHub pull issue would hang the
   job.

Fix landed at `hashicorpvault/vault-unseal-cronjob.yaml` (in Git, but **the Argo
wire-up is still TODO — see "Open blockers / B2" above**):

- pinned `curlimages/curl:8.10.1`
- `set -eu` strict shell, with a 6×5 s readiness loop before unseal
- explicit "is it really unsealed now?" verification at the end, `exit 1` on failure
  (so the Job is correctly marked Failed and the next CronJob retry runs)
- `activeDeadlineSeconds: 120`, `backoffLimit: 2`, resource requests/limits set
- still needs `vault-unseal-keys` Secret (3 keys, sealed-secrets-managed) — unchanged

**Status (2026-04-26):** in-cluster CronJob is healthy and unsealing on schedule, but is
still labelled `app.kubernetes.io/managed-by: kubectl`. The follow-up to bring it under
ArgoCD is described in "Open blockers / B2" — recommended path is to convert
`hashicorpvault.yaml` to a multi-source Application that owns chart + companion
manifests in one Application.

### bootstrap-qa (app-of-apps) revision cache

After force-pushing a rollback commit, bootstrap-qa was observed to remain synced at
the previous revision for > 10 min despite `refresh=hard` annotations and repo-server
pod restarts. If this happens, options in order of preference:

1. Wait for the 3 min auto-polling cycle.
2. `kubectl -n argocd-qa rollout restart deployment/argocd-repo-server` to flush the
   clone cache.
3. Directly patch the child Application CR's `targetRevision` and (only as a last resort)
   toggle `syncPolicy.automated.selfHeal: false` on it, to break the selfHeal loop.

### authentik 2025.12.4 → 2026.2.x (year release — breaking)
Authentik's yearly release boundary bundles database migrations, API deprecations,
and UI changes. PG15 → 17 + storage migration is already done (see above). Sequence:

1. Take a Longhorn snapshot of the `data-authentik-postgresql-0` PVC (now on
   `longhorn-retain`, which supports snapshots — that's why we did the storage migration).
2. Review [authentik 2026.2 release notes](https://docs.goauthentik.io/docs/releases).
3. Open Renovate dashboard issue, tick the authentik 2026.x checkbox, review the
   rendered diff (chart-side migration scripts, removed CRDs, etc.).
4. Merge → bootstrap-qa fans out → ArgoCD applies.
5. Verify all providers/flows/stages still load in the admin UI; smoke-test
   mediaradar / grafana / argocd UI HTTP 302 round-trip.
6. If the bump fails, scale workers to 0, restore the snapshot via Longhorn, scale
   workers back up. Same approach as Path B but using Longhorn snapshots instead of
   pg_dumpall (now possible because we're off local-path).

## Why these aren't all auto-merged

`renovate.json` in the repo root gates majors and critical-minor bumps behind the
`dependencyDashboardApproval: true` flag. That means you see them in the dashboard issue,
tick the box for the ones you're ready to absorb, Renovate opens a PR, you review the
rendered manifest diff, merge → ArgoCD's bootstrap-qa fans it out. That is the intended
long-term flow; this roadmap just captures the current queue.
