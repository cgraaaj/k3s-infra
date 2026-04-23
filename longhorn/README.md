# Longhorn

Cluster-wide distributed block storage. Managed via the
[`longhorn` ArgoCD Application](../argo-registry/qa/manifests/infra/longhorn.yaml)
which pulls values from [`values.yaml`](values.yaml) in this directory.

## Default StorageClass

See [`storageclass.yaml`](storageclass.yaml).

## Post-upgrade cleanup

Helm upgrades sometimes leave orphaned engine images / DaemonSets. Run the
following after a chart bump to clear stale resources:

```bash
# Identify stale engine-image DaemonSet
kubectl get ds -n longhorn-system

# Delete it (replace the tag with the one reported as "deprecated")
kubectl delete ds engine-image-ei-51cc7b9c -n longhorn-system

# Do the same for the Longhorn engineimages CRD
kubectl get engineimages.longhorn.io -n longhorn-system
kubectl delete engineimages.longhorn.io ei-51cc7b9c -n longhorn-system

# Roll all pods to pick up the new image
kubectl delete pod -n longhorn-system --all
```
