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
| **authentik**                 | `2025.12.4` ⬆ from `2025.2.4` (PG15→17 + local-path→longhorn-retain done 2026-04-24) | `2026.2.2` | T3-step-1 | `2025.12.4` → `2026.2.2` (year-release, see runbook) |
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
