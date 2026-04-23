# ArgoCD (dev cluster)

Declarative source for the two ArgoCD installs that serve this cluster:

| Path                     | Purpose                                                             |
| ------------------------ | ------------------------------------------------------------------- |
| [qa/](qa/)               | Kustomize + IngressRoute for **`argocd-qa`** (primary active install; UI at `argocd.qa.cgraaaj.in`). |
| [prod/](prod/)           | Raw HA install + IngressRoute for the future prod ArgoCD.            |
| [argocd-cmd-params-cm.yaml](argocd-cmd-params-cm.yaml) | ConfigMap patch enabling `server.insecure: "true"` so Traefik can terminate TLS upstream. |

## Operational notes

- Apply `argocd-cmd-params-cm.yaml` on top of a fresh install, then restart the
  `argocd-server` pod. This removes the bundled Redis config and forces the
  server into insecure (HTTP) mode so Traefik can terminate TLS.
- To retrieve the bootstrap admin password:

  ```bash
  kubectl -n argocd-qa get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d; echo
  ```

- Once logged in for the first time, change the admin password and remove
  `argocd-initial-admin-secret`.
