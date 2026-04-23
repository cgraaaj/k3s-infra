# Istio Grafana Dashboards

Official Istio dashboards for Grafana.

## Import Dashboards to Your Existing Grafana

### Option 1: Import via Grafana UI (Recommended)

1. Access your Grafana: https://grafana.dev.cgraaaj.in
2. Go to **Dashboards** → **Import**
3. Import these official Istio dashboard IDs from grafana.com:

| Dashboard | ID | Description |
|-----------|-----|-------------|
| Istio Control Plane Dashboard | `7645` | Istiod metrics |
| Istio Mesh Dashboard | `7639` | Overall mesh metrics |
| Istio Service Dashboard | `7636` | Per-service metrics |
| Istio Workload Dashboard | `7630` | Per-workload metrics |
| Istio Performance Dashboard | `11829` | Performance metrics |

**Steps:**
```
1. Click "+ Import" in Grafana
2. Enter dashboard ID (e.g., 7639)
3. Click "Load"
4. Select your Prometheus data source
5. Click "Import"
```

### Option 2: Add Dashboards to kube-prometheus-stack Values

Edit your `monitoring/values.yaml` to include Istio dashboards automatically:

```yaml
grafana:
  enabled: true
  fullnameOverride: grafana
  # ... existing config ...
  
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
      - name: 'default'
        orgId: 1
        folder: ''
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/default
      - name: 'istio'
        orgId: 1
        folder: 'Istio'
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/istio
  
  dashboards:
    istio:
      istio-mesh:
        gnetId: 7639
        revision: 202
        datasource: Prometheus
      istio-service:
        gnetId: 7636
        revision: 202
        datasource: Prometheus
      istio-workload:
        gnetId: 7630
        revision: 202
        datasource: Prometheus
      istio-control-plane:
        gnetId: 7645
        revision: 202
        datasource: Prometheus
      istio-performance:
        gnetId: 11829
        revision: 202
        datasource: Prometheus
```

Then upgrade your kube-prometheus-stack:
```bash
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f monitoring/values.yaml
```

### Option 3: Manual JSON Import

Download dashboard JSONs from Grafana.com and import them:

```bash
# Download Istio dashboards
curl -o istio-mesh.json https://grafana.com/api/dashboards/7639/revisions/202/download
curl -o istio-service.json https://grafana.com/api/dashboards/7636/revisions/202/download
curl -o istio-workload.json https://grafana.com/api/dashboards/7630/revisions/202/download
curl -o istio-control-plane.json https://grafana.com/api/dashboards/7645/revisions/202/download

# Import via Grafana UI: Dashboards → Import → Upload JSON
```

## Dashboard Descriptions

### 1. Istio Mesh Dashboard (ID: 7639)
- **Shows:** Overall service mesh health
- **Metrics:**
  - Global request volume
  - Global success rate
  - 4xx/5xx errors
- **Use for:** High-level mesh overview

### 2. Istio Service Dashboard (ID: 7636)
- **Shows:** Per-service metrics
- **Metrics:**
  - Request rate per service
  - Success rate per service
  - Request duration (p50, p90, p99)
- **Use for:** Debugging specific services

### 3. Istio Workload Dashboard (ID: 7630)
- **Shows:** Per-workload (deployment/pod) metrics
- **Metrics:**
  - Request rate per workload
  - Response time per workload
  - Inbound/outbound traffic
- **Use for:** Workload-level troubleshooting

### 4. Istio Control Plane Dashboard (ID: 7645)
- **Shows:** Istiod health
- **Metrics:**
  - Pilot proxy pushes
  - Configuration sync status
  - Memory/CPU usage
- **Use for:** Control plane monitoring

### 5. Istio Performance Dashboard (ID: 11829)
- **Shows:** Detailed performance metrics
- **Metrics:**
  - Latency percentiles
  - Connection pools
  - Circuit breaker status
- **Use for:** Performance optimization

## Verification

After importing, verify dashboards work:

1. Go to **Dashboards** → **Browse**
2. Look for "Istio" folder
3. Open any Istio dashboard
4. You should see metrics once Istio is deployed and generating traffic

## Troubleshooting

**No data in dashboards:**
1. Verify Prometheus is scraping Istio metrics:
   ```bash
   kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
   # Open http://localhost:9090
   # Go to Status → Targets
   # Check for istio-system targets
   ```

2. Verify ServiceMonitors are deployed:
   ```bash
   kubectl get servicemonitor -n istio-system
   ```

3. Check if Istio pods are running:
   ```bash
   kubectl get pods -n istio-system
   ```

**Wrong data source:**
- Edit dashboard settings → Variables
- Update data source to match your Prometheus instance name

## Next Steps

1. Import dashboards to Grafana
2. Deploy Istio (if not already)
3. Deploy applications with Istio sidecars
4. Generate traffic to see metrics
5. Explore dashboards in Grafana




