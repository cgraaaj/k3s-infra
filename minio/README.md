# MinIO

S3-compatible object storage. Managed via the
[`minio` ArgoCD Application](../argo-registry/qa/manifests/infra/minio.yaml)
(root credentials are supplied as inline Helm values in that Application).

## Install reference (historical — pre-ArgoCD)

```bash
helm install \
  --namespace minio \
  --set rootUser=rootuser,rootPassword=rootpass1345 \
  minio minio/minio \
  -f ./minio/values.yaml
```

After the initial install the credentials **must** match the values in the
ArgoCD Application's `helm.values` block; otherwise the `minio-post-install`
Job fails with *"Server not initialized yet"*.
