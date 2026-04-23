# Archive

Historical reference material — **not actively deployed** and **not watched by
any ArgoCD Application**. Kept in-tree so past configurations and examples
remain discoverable without cluttering the repo root.

## Layout

```
docs/archive/
└── legacy-manifests/
    ├── coder/        # Coder.com IDE ingress (retired deployment)
    ├── examples/     # Istio integration examples + mediaradar-istio-gateway.yaml
    ├── ignite/       # Apache Ignite StatefulSet + config (retired)
    ├── jenkins/      # Jenkins pod templates (migrated to GitLab Runner)
    ├── nginx-test/   # Ingress connectivity smoke test (one-off)
    └── npm/          # Nginx Proxy Manager ExternalName shim (retired)
```

## Handling

- Do **not** `kubectl apply` from here without first verifying nothing already
  owns those resources in the cluster.
- If a resource here needs to come back, promote it to the appropriate
  top-level directory and wire it through [argo-registry/qa/manifests/](../../argo-registry/qa/manifests/)
  as an ArgoCD Application.
- Safe to delete entirely once cluster history is no longer useful as reference.
