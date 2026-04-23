# Istio ServiceMonitors for Prometheus Operator

These ServiceMonitor and PodMonitor CRDs configure your existing Prometheus Operator to scrape Istio metrics.

## Components

1. **servicemonitor-istiod.yaml** - Scrapes Istiod (control plane) metrics
2. **servicemonitor-envoy.yaml** - Scrapes all Envoy sidecar proxies
3. **servicemonitor-ingress.yaml** - Scrapes Istio Ingress Gateway metrics

## How It Works

Your existing kube-prometheus-stack uses Prometheus Operator, which watches for:
- `ServiceMonitor` CRDs - for scraping Services
- `PodMonitor` CRDs - for scraping Pods directly

These CRDs automatically configure Prometheus scrape configs without redeploying Prometheus!

## Label Requirement

All ServiceMonitors/PodMonitors must have the label:
```yaml
labels:
  release: prometheus
```

This matches your kube-prometheus-stack release name (from values.yaml: `fullnameOverride: prometheus`).

## Verification

After deployment, verify metrics are being scraped:

```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Open http://localhost:9090
# Go to Status > Targets
# Look for:
# - istio-system/istiod
# - istio-system/istio-ingressgateway
# - envoy-stats (across multiple namespaces)
```

## Istio Metrics Available

Once scraped, you'll have access to metrics like:
- `istio_requests_total` - Request count
- `istio_request_duration_milliseconds` - Request latency
- `istio_request_bytes` - Request size
- `istio_response_bytes` - Response size
- `pilot_xds_pushes` - Control plane push events
- And 100+ more Istio/Envoy metrics




