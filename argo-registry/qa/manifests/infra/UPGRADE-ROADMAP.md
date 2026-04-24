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
| **vault** (hashicorpvault)    | `0.32.0` ⬆ from `0.30.1` | `0.32.0` | T2 | — |
| **cert-manager**              | `v1.18.6` ⬆ from `v1.17.4` | `v1.20.2` | T3-step-1 | `v1.19.5` → `v1.20.2` |
| **istio-base / istiod / gateway** | `1.25.5` ⬆ from `1.23.6` | `1.29.2` | T3-step-1 (N-2 skip) | `1.27.x` → `1.29.x` |
| **longhorn**                  | `1.9.2` ⬆ from `1.8.2`  | `1.11.1` | T3-step-1 | `1.10.x` → `1.11.x` |
| **authentik**                 | git: `2025.2.4` / runtime: `2025.12.4` (rollback failed — see runbook) | `2026.2.2` | — | Roll-forward to `2025.12.4` in git + override PG image to bitnami `15.x`, OR do PG15→17 migration. Until then: `selfHeal: false` on the Application CR. |
| **traefik**                   | `36.3.0` ⬆ from `34.4.1` | `39.0.8` | T3-step-1 | `37.x` → `38.x` → `39.x` |
| **kube-prometheus-stack**     | `75.15.2`     | `84.0.0`       | — | T3 — defer, CRD migration needed |
| **kiali-server**              | `1.89.0`      | `2.25.0`       | — | T3 — v1→v2 full rewrite, defer |
| **gitlab-runner**             | `0.68.1`      | `0.88.1`       | — | T3 — GitLab Runner 17→18, defer |

## Runbooks for remaining T3 migrations

### Istio 1.25 → 1.27 → 1.29 (N-2 rule)
Istio supports skipping at most 2 minor versions. Sequence:

1. Merge this PR and confirm 1.25.5 is Healthy (watch `istiod` pods, `kubectl get proxy-status`,
   Kiali dashboard for traffic continuity).
2. Wait ≥ 1 week on 1.25 in dev before the next step.
3. Bump all three (`base`, `istiod`, `gateway`) to `1.27.9` in one commit. Gateway last.
4. Same wait.
5. Bump to `1.29.2`.

**Pre-flight before each step**: `istioctl x precheck` from a pod with `istioctl` installed.

### cert-manager 1.18 → 1.19 → 1.20
cert-manager supports N+1 minor bumps directly, but each bump may add/deprecate CRD fields.

1. Confirm 1.18.6 Healthy.
2. **Fix the pre-existing CRD drift first** (cluster still runs v1.12.10 CRDs from a manual
   `kubectl apply` long ago): flip `helm.skipCrds: false` in `cert-manager.yaml`, sync,
   watch `Certificate`/`Issuer` reconcile.
3. Bump chart to `v1.19.5`, wait for stability, then `v1.20.2`.

### longhorn 1.9 → 1.10 → 1.11
**Storage — never skip minors**. Each bump requires:

1. Take a [Longhorn backup snapshot](https://longhorn.io/docs/1.11.1/snapshots-and-backups/) of every PV first.
2. Confirm no volume is in `Detached` or `Degraded` state before the bump.
3. Bump chart one minor.
4. Watch `longhorn-manager` pods roll, then `engine-image-*` DaemonSet re-roll.
5. Test a volume detach/attach cycle before proceeding.

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

### authentik: PostgreSQL 15 → 17 migration **REQUIRED** before any chart bump past `2025.2.4`

**Trap discovered during `2025.12.4` attempt (2026-04-23):** starting in authentik chart
`2025.10.x`, the project dropped the bitnami/postgresql subchart (which ships
`bitnami/postgresql:15.x`) and switched to the upstream `docker.io/library/postgres:17`
image. The helm upgrade silently changes the postgres image in the StatefulSet, but the
existing PV is a PG15 data directory, so the new pod crash-loops with:

```
FATAL: database files are incompatible with server
DETAIL: The data directory was initialized by PostgreSQL version 15,
         which is not compatible with this version 17.7
```

To move past `2025.2.4` you must migrate the data first:

1. **Snapshot** the Longhorn PV backing `data-authentik-postgresql-0` (RTO backup).
2. Scale authentik-server and authentik-worker to 0 to stop writes.
3. `kubectl -n authentik exec authentik-postgresql-0 -- pg_dumpall -U authentik > authentik-pg15.sql`
4. Scale the StatefulSet down, delete the PVC, let Helm re-create with PG17.
5. `kubectl -n authentik cp authentik-pg15.sql authentik-postgresql-0:/tmp/ && kubectl -n authentik exec -it authentik-postgresql-0 -- psql -U authentik -f /tmp/authentik-pg15.sql`
6. Scale server + worker back up, verify admin UI.
7. Then bump chart `2025.2.4 → 2025.12.4 → 2026.2.2`.

**Why automated rollback on this run was non-trivial:** the authentik Application has
`syncPolicy.automated.selfHeal: true`, which kept pushing the StatefulSet back to the
new (broken) 2025.12.4 template. We temporarily disabled `selfHeal` on the authentik
Application CR so the rollback could stick.

**Critical follow-up finding (post-mortem 2026-04-23 evening):** the chart rollback to
`2025.2.4` cannot actually take effect, because the brief `2025.12.4` run **already
migrated the application schema** (notably renamed
`authentik_core_authenticatedsession.session_key` → `session_id`). The 2025.2.4 server
container therefore crash-loops with `column ... session_key does not exist` against
the migrated DB. Two ReplicaSets coexist in the cluster:

| RS | Image | State |
|----|-------|-------|
| `authentik-server-7bd5ccc8bc` | `goauthentik/server:2025.2.4` (git desired) | 0/1, fails readiness with the schema error |
| `authentik-server-84867d7d87` | `goauthentik/server:2025.12.4` (orphan from upgrade) | 1/1 — the only pod actually serving outpost / forward-auth |

If `selfHeal` (or `prune`) is ever turned back on while git is still at `2025.2.4`,
ArgoCD will GC the only working pod and **all auth-gated apps** (mediaradar, grafana,
optionscope, argocd, traefik dashboard, etc.) will go dark cluster-wide. `prune` and
`selfHeal` are therefore both intentionally pinned to `false` in
`argo-registry/qa/manifests/infra/authentik.yaml` until one of the two paths below is
executed.

**Recovery options (pick one):**

A. **Roll FORWARD in git to `2025.12.4`** (matches what's actually running) and *override
   the postgresql image* in `k3s-infra/authentik/values.yaml` so the chart keeps using
   `bitnami/postgresql:15.8.0-debian-12-r18` instead of `library/postgres:17`. This is the
   lowest-risk path because no DB migration runs. Then re-enable `selfHeal: true` and
   `prune: true` on the Application.

B. **Execute the PG15 → PG17 migration** documented above (snapshot, `pg_dumpall`, scale
   down, recreate PVC, `psql -f`, scale up). After PG17 is live, the rolled-forward
   chart 2025.12.4 (with stock `library/postgres:17`) will reconcile cleanly.

Until A or B is done, do NOT run `kubectl -n argocd-qa app sync authentik` with
`Prune=true` or toggle `automated.prune/selfHeal: true`.

### cert-manager v1.17 → v1.18: needs `Replace=true` sync option

The jetstack chart renders the `Deployment.spec.strategy` field with a `$retainKeys`
merge directive that trips ArgoCD's SSA (`field not declared in schema`). Solution is to
sync with `Replace=true` once (fallback to client-side apply):

```
kubectl -n argocd-qa patch applications.argoproj.io cert-manager --type merge \
  -p '{"operation":{"sync":{"syncOptions":["RespectIgnoreDifferences=true","Replace=true"]}}}'
```

Subsequent patch bumps within v1.18 don't need Replace=true again.

### bootstrap-qa (app-of-apps) revision cache

After force-pushing a rollback commit, bootstrap-qa was observed to remain synced at
the previous revision for > 10 min despite `refresh=hard` annotations and repo-server
pod restarts. If this happens, options in order of preference:

1. Wait for the 3 min auto-polling cycle.
2. `kubectl -n argocd-qa rollout restart deployment/argocd-repo-server` to flush the
   clone cache.
3. Directly patch the child Application CR's `targetRevision` and (only as a last resort)
   toggle `syncPolicy.automated.selfHeal: false` on it, to break the selfHeal loop.

### authentik 2025.x → 2026.2 (year release — breaking)
Authentik's yearly release boundary bundles database migrations, API deprecations,
and UI changes. **Do the PG15 → 17 migration first (see above), then:**

1. Snapshot the `authentik-postgresql-*` PV via Longhorn.
2. Review [authentik 2026.2 release notes](https://docs.goauthentik.io/docs/releases).
3. Bump chart.
4. Verify all providers/flows/stages still load in the admin UI.

## Why these aren't all auto-merged

`renovate.json` in the repo root gates majors and critical-minor bumps behind the
`dependencyDashboardApproval: true` flag. That means you see them in the dashboard issue,
tick the box for the ones you're ready to absorb, Renovate opens a PR, you review the
rendered manifest diff, merge → ArgoCD's bootstrap-qa fans it out. That is the intended
long-term flow; this roadmap just captures the current queue.
