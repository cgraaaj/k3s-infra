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
| **authentik**                 | `2025.12.4` ⬆ from `2025.2.4` | `2026.2.2` | T3-step (within-year) | `2026.2.x` (breaking year release) |
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

### authentik 2025.12 → 2026.2 (year release — breaking)
Authentik's yearly release boundary usually bundles database migrations, API deprecations,
and UI changes. **Back up the PostgreSQL database before the bump.**

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
