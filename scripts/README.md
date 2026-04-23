# Scripts

Operational helper scripts for the k3s dev cluster. All scripts assume the
current shell has a working `kubectl` context pointed at the cluster
(`https://10.19.94.151:6443`).

| Script                                                             | Purpose                                                                                                     |
| ------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| [deploy-istio.sh](deploy-istio.sh)                                 | One-shot deployment of the Istio service mesh via ArgoCD. See [docs/istio/README.md](../docs/istio/README.md). |
| [setup-global-registry-access.sh](setup-global-registry-access.sh) | Distributes the `registry.cgraaaj.in` pull secret to a curated list of namespaces and patches the `default` ServiceAccount. |

## Usage

```bash
# Istio stack (idempotent)
./scripts/deploy-istio.sh

# Registry credential fan-out (re-run after adding a new namespace)
./scripts/setup-global-registry-access.sh
```

## Notes

- `setup-global-registry-access.sh` still reads the dockerconfig from
  `argo-registry/dockerconfig.json` (absolute path, unchanged).
- Treat these scripts as **imperative convenience wrappers**; the
  source of truth for anything persistent is the ArgoCD Applications in
  [argo-registry/qa/manifests/](../argo-registry/qa/manifests/).
- Recommended follow-up: replace the static registry secret with
  External Secrets Operator backed by HashiCorp Vault so the credential is
  rotated centrally instead of flashed into every namespace.
