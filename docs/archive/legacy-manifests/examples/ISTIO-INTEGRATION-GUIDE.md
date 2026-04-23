# Integrating Your Application with Istio

This guide explains how to integrate your `mediaradar` application with the Istio service mesh.

## Prerequisites

✅ Istio infrastructure deployed (via ArgoCD applications in `argo-registry/qa/manifests/infra/`)
✅ Application repository: https://github.com/cgraaaj/mediaradar.git

## Step 1: Enable Sidecar Injection

Add the `istio-injection` label to your namespace. This tells Istio to automatically inject sidecar proxies into your pods.

### Option A: Update ArgoCD Application (Recommended)

Edit `/home/cgraaaj/Projects/k3s-projects/argo-registry/qa/manifests/apps/mediaradar-k8s.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mediaradar
  namespace: argocd-qa
spec:
  project: apps
  source:
    repoURL: https://github.com/cgraaaj/mediaradar.git
    path: k8s
    targetRevision: master
    helm:
      valueFiles:
        - values-qa.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: mediaradar
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
    automated: 
      prune: true
      selfHeal: true
    # Add this section to enable Istio injection:
    managedNamespaceMetadata:
      labels:
        istio-injection: enabled
```

### Option B: Manual Label (Quick Test)

```bash
kubectl label namespace mediaradar istio-injection=enabled
```

## Step 2: Add Istio Resources to Your Application Repo

In your `mediaradar` repository, add Istio Gateway and VirtualService configurations.

### Directory Structure

```
mediaradar/
├── k8s/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── istio/                    # ← Add this directory
│   │   ├── gateway.yaml
│   │   ├── virtualservice.yaml
│   │   └── destinationrule.yaml  # Optional
│   ├── values.yaml
│   └── values-qa.yaml
```

### Example Gateway Configuration

Create `k8s/istio/gateway.yaml`:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: mediaradar-gateway
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "mediaradar-qa.local"
```

### Example VirtualService Configuration

Create `k8s/istio/virtualservice.yaml`:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: mediaradar
spec:
  hosts:
  - "mediaradar-qa.local"
  gateways:
  - mediaradar-gateway
  http:
  - match:
    - uri:
        prefix: /api
    route:
    - destination:
        host: mediaradar-api
        port:
          number: 8080
    retries:
      attempts: 3
      perTryTimeout: 2s
    timeout: 10s
```

**See `mediaradar-istio-gateway.yaml` for complete examples with advanced features.**

## Step 3: Restart Your Pods

After enabling sidecar injection, restart your pods to inject the Envoy proxy:

```bash
kubectl rollout restart deployment -n mediaradar
```

### Verify Sidecar Injection

```bash
# Check that pods now have 2 containers (app + istio-proxy)
kubectl get pods -n mediaradar

# Expected output:
# NAME                           READY   STATUS
# mediaradar-api-xxx             2/2     Running  # ← Note: 2/2 instead of 1/1
```

## Step 4: Access Your Application

### Get Ingress Gateway External IP

```bash
kubectl get svc -n istio-system istio-ingressgateway

# Example output:
# NAME                   TYPE           EXTERNAL-IP     PORT(S)
# istio-ingressgateway   LoadBalancer   192.168.1.100   80:30080/TCP,443:30443/TCP
```

### Test Access

```bash
# Using the external IP
curl http://192.168.1.100 -H "Host: mediaradar-qa.local"

# Or add to /etc/hosts:
echo "192.168.1.100 mediaradar-qa.local" | sudo tee -a /etc/hosts

# Then access via browser:
http://mediaradar-qa.local
```

## Step 5: Monitor with Kiali

### Access Kiali Dashboard

```bash
# Get Kiali service
kubectl get svc -n istio-system kiali-server

# Port-forward to access (or use LoadBalancer IP)
kubectl port-forward -n istio-system svc/kiali-server 20001:20001

# Access in browser:
http://localhost:20001/kiali
```

### Kiali Features

- 📊 **Service Graph** - Visualize traffic flow
- 📈 **Metrics** - Request rates, latency, error rates
- 🔍 **Traces** - Distributed tracing (if configured)
- ⚙️ **Configuration** - Validate Istio configs
- 🔐 **Security** - View mTLS status

## Common Patterns

### Canary Deployment

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: mediaradar-canary
spec:
  hosts:
  - mediaradar-api
  http:
  - match:
    - headers:
        x-version:
          exact: "canary"
    route:
    - destination:
        host: mediaradar-api
        subset: v2
  - route:
    - destination:
        host: mediaradar-api
        subset: v1
      weight: 90
    - destination:
        host: mediaradar-api
        subset: v2
      weight: 10  # Send 10% traffic to canary
```

### Circuit Breaking

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: mediaradar-circuit-breaker
spec:
  host: mediaradar-api
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 50
        maxRequestsPerConnection: 2
    outlierDetection:
      consecutiveErrors: 5
      interval: 30s
      baseEjectionTime: 30s
```

### Request Timeout & Retry

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: mediaradar-resilience
spec:
  hosts:
  - mediaradar-api
  http:
  - route:
    - destination:
        host: mediaradar-api
    timeout: 10s
    retries:
      attempts: 3
      perTryTimeout: 2s
      retryOn: 5xx,reset,connect-failure
```

## Troubleshooting

### Check Sidecar Status

```bash
# Describe pod to see sidecar
kubectl describe pod -n mediaradar <pod-name>

# Check istio-proxy logs
kubectl logs -n mediaradar <pod-name> -c istio-proxy
```

### Analyze Configuration

```bash
# Install istioctl (if not already)
curl -L https://istio.io/downloadIstio | sh -
cd istio-*/bin
./istioctl analyze -n mediaradar

# Check proxy configuration
./istioctl proxy-config routes <pod-name> -n mediaradar
```

### Common Issues

**Issue: Pods stuck in Init state**
- Check: `kubectl logs <pod> -c istio-init`
- Solution: Ensure CNI is compatible with Istio

**Issue: 503 errors from gateway**
- Check: Gateway and VirtualService host matching
- Verify: `kubectl get gateway,virtualservice -n mediaradar`

**Issue: mTLS errors**
- Check: `istioctl x describe pod <pod-name> -n mediaradar`
- Solution: Ensure all services have sidecars injected

## Environment-Specific Configuration

### QA (K3s ARM)

```yaml
# values-qa.yaml
istio:
  enabled: true
  gateway:
    host: "mediaradar-qa.local"
```

### Production (OKD x86)

```yaml
# values-prod.yaml
istio:
  enabled: true
  gateway:
    host: "mediaradar.example.com"
  tls:
    enabled: true
    secretName: mediaradar-tls
```

## Next Steps

1. ✅ Enable mTLS enforcement
2. ✅ Set up authorization policies
3. ✅ Configure distributed tracing (Jaeger)
4. ✅ Implement traffic splitting for canary deployments
5. ✅ Set up Grafana dashboards for metrics

## Resources

- [Istio Documentation](https://istio.io/latest/docs/)
- [Kiali Documentation](https://kiali.io/docs/)
- [Istio Gateway API](https://istio.io/latest/docs/reference/config/networking/gateway/)
- [Traffic Management](https://istio.io/latest/docs/concepts/traffic-management/)




