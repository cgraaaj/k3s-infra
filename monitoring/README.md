# Monitoring (kube-prometheus-stack + Loki)

The observability stack for the dev cluster. Managed via the
[`prometheus` ArgoCD Application](../argo-registry/qa/manifests/infra/prometheus.yaml)
and the [`loki` ArgoCD Application](../argo-registry/qa/manifests/infra/loki.yaml).

## Layout

| Path                                                | Purpose                                                        |
| --------------------------------------------------- | -------------------------------------------------------------- |
| [`values.yaml`](values.yaml)                        | `kube-prometheus-stack` Helm values (Prometheus, Grafana, Alertmanager) |
| [`ingress.yaml`](ingress.yaml)                      | Traefik `IngressRoute` for Grafana (`grafana.dev.cgraaaj.in`)  |
| [`kiali-ingress.yaml`](kiali-ingress.yaml)          | Traefik `IngressRoute` for Kiali (`kiali.dev.cgraaaj.in`)      |
| [`pvc.yaml`](pvc.yaml)                              | Longhorn PVC for Grafana                                       |
| [`alerts/`](alerts/)                                | `PrometheusRule` manifests                                     |
| [`alert-router/`](alert-router/)                    | Custom alert webhook router (Python + Dockerfile)              |
| [`alertmanager-router-config.yaml`](alertmanager-router-config.yaml) | Alertmanager routing tree                       |
| [`istio-dashboards/`](istio-dashboards/)            | Grafana dashboards for Istio — see [README](istio-dashboards/README.md) for the full architecture + onboarding flow |
| [`istio-servicemonitors/`](istio-servicemonitors/)  | `ServiceMonitor` / `PodMonitor` CRs for Istio scraping (label `release: prometheus`) |
| [`loki-stack/`](loki-stack/)                        | Loki Helm values + PVC                                         |

## Access

- Grafana UI: https://grafana.dev.cgraaaj.in (Authentik SSO).
- Prometheus UI (port-forward only): `kubectl -n monitoring port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090`.
- Alertmanager (port-forward only): `kubectl -n monitoring port-forward svc/alertmanager 9093:9093`.

## Post-install reference

Retrieve the bootstrap Grafana admin password (only if Authentik SSO is unavailable):

```bash
kubectl -n monitoring get secret prometheus-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d; echo
```

### Reusing a Released PV

If Grafana is re-installed and the previous Longhorn PV is stuck in `Released`:

```bash
kubectl patch pv <pv-name> -p '{"spec":{"claimRef": null}}'
kubectl get pv   # should report Available
kubectl apply -f monitoring/pvc.yaml
```

See the upstream operator docs for Prometheus/Alertmanager configuration:
https://github.com/prometheus-operator/kube-prometheus
