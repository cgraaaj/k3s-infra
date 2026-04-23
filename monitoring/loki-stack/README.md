# Loki Stack

Log aggregation backend for the cluster, using `grafana/loki-stack` with an
S3 bucket on the in-cluster MinIO as the chunk store.

## Prerequisites

1. The MinIO `loki` bucket must exist **before** installing/upgrading Loki;
   otherwise the chunk writer panics on startup. Create it via the MinIO
   console (`minio.dev.cgraaaj.in`) or `mc mb local/loki`.
2. Longhorn `StorageClass` must be the default — `pvc.yaml` relies on it.

## Install / upgrade (manual reference — ArgoCD does this automatically)

```bash
helm upgrade --install loki \
  --namespace=loki \
  grafana/loki-stack \
  --set loki.image.tag=2.9.3 \
  -f monitoring/loki-stack/values.yaml
```

The pinned tag `2.9.3` works around
[loki#11557](https://github.com/grafana/loki/issues/11557) which surfaces as an
"unidentified error" with newer 2.9.x images.
