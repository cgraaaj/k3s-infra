# Argo Registry — GitOps Source of Truth

ArgoCD `Application` and `AppProject` manifests that describe everything
ArgoCD synchronises onto the cluster.

## Layout

```
argo-registry/
├── dockerconfig.json    # (untracked) registry.cgraaaj.in pull secret
├── qa/manifests/
│   ├── apps/            # Application Helm/Kustomize/raw app manifests
│   ├── cronjobs/        # Scheduled jobs (sa-cache-manager, etc.)
│   ├── infra/           # Infrastructure Helm releases (Traefik, cert-manager,
│   │                    # Longhorn, Vault, Prometheus, Loki, Authentik, MinIO,
│   │                    # kubernetes-replicator, Istio, ArgoCD Image Updater)
│   └── projects/        # AppProject RBAC boundaries
└── prod/manifests/      # Placeholder for prod cluster (future)
```

## Registry pull secret

`dockerconfig.json` contains a Docker config auth entry for
`registry.cgraaaj.in`. It is listed in [`.gitignore`](../.gitignore) and must
never be committed.

To distribute the pull secret to a single namespace:

```bash
kubectl create secret generic regcred \
  --from-file=.dockerconfigjson=argo-registry/dockerconfig.json \
  --type=kubernetes.io/dockerconfigjson \
  -n <namespace>
```

To fan it out across the commonly used namespaces, use
[../scripts/setup-global-registry-access.sh](../scripts/setup-global-registry-access.sh).

> **Recommended follow-up:** rotate the current robot token and migrate this
> credential to External Secrets Operator backed by HashiCorp Vault so the
> `dockerconfig.json` file on disk can be deleted entirely.

## Apply order (bootstrap)

```bash
# Projects first (RBAC boundaries)
kubectl apply -f argo-registry/qa/manifests/projects/

# Then infra (Helm releases are idempotent; ArgoCD owns reconcile order
# via sync-waves internally)
kubectl apply -f argo-registry/qa/manifests/infra/

# Finally apps + cronjobs
kubectl apply -f argo-registry/qa/manifests/apps/
kubectl apply -f argo-registry/qa/manifests/cronjobs/
```

See [qa/manifests/infra/README.md](qa/manifests/infra/README.md) for
component-specific notes.
