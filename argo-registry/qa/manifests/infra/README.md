# Istio Infrastructure Setup

This directory contains ArgoCD Application manifests for deploying Istio service mesh on K3s ARM64 cluster.

## Components

### Core Istio Components
1. **istio-base.yaml** - Istio CRDs (Custom Resource Definitions)
2. **istiod.yaml** - Istio control plane (deployed on control plane nodes: crystalmaiden, pudge)
3. **istio-ingressgateway.yaml** - Ingress gateway (deployed on worker nodes: invoker, juggernaut, mirana)

### Observability Stack
4. **prometheus.yaml** - Metrics collection and storage (with Longhorn persistence)
5. **kiali.yaml** - Service mesh dashboard and visualization

## Deployment Order

ArgoCD will handle dependencies automatically, but the logical order is:

```
1. istio-base (CRDs)
   ↓
2. istiod (control plane)
   ↓
3. istio-ingressgateway (data plane)
   ↓
4. prometheus + kiali (observability)
```

## Resource Requirements

| Component | CPU Request | Memory Request | Memory Limit |
|-----------|-------------|----------------|--------------|
| istiod (2 replicas) | 200m × 2 | 512Mi × 2 | 1Gi × 2 |
| ingress-gateway (2 replicas) | 100m × 2 | 128Mi × 2 | 512Mi × 2 |
| prometheus | 100m | 256Mi | 1Gi |
| kiali | 50m | 128Mi | 512Mi |
| **Total** | ~800m | ~2.2GB | ~5GB |

On your 8GB nodes, this leaves ~5.8GB for applications.

## Node Placement Strategy

- **Control Plane Nodes** (crystalmaiden, pudge):
  - istiod replicas

- **Worker Nodes** (invoker, juggernaut, mirana - 8GB each):
  - istio-ingressgateway replicas (with anti-affinity)
  - prometheus
  - kiali
  - application pods with sidecars

- **Storage Nodes** (k3s-longhorn-01, k3s-longhorn-02 - 1GB each):
  - No Istio workloads (dedicated to Longhorn)

## Deployment

All applications are managed by ArgoCD and will auto-sync:

```bash
# Apply the infrastructure project first
kubectl apply -f /home/cgraaaj/Projects/k3s-projects/argo-registry/qa/manifests/projects/appproject-infrastructure.yaml

# Then apply all Istio applications
kubectl apply -f /home/cgraaaj/Projects/k3s-projects/argo-registry/qa/manifests/infra/

# Check deployment status
kubectl get pods -n istio-system

# Access Kiali dashboard (once deployed)
kubectl get svc -n istio-system kiali-server
# Access via LoadBalancer IP
```

## Verification

```bash
# Check Istio installation
istioctl version
istioctl proxy-status

# Check control plane status
kubectl get pods -n istio-system

# Expected output:
# NAME                                    READY   STATUS
# istiod-xxxx                             1/1     Running
# istiod-xxxx                             1/1     Running
# istio-ingressgateway-xxxx               1/1     Running
# istio-ingressgateway-xxxx               1/1     Running
# prometheus-server-xxxx                  1/1     Running
# kiali-server-xxxx                       1/1     Running
```

## Next Steps

1. **Enable sidecar injection** for your application namespaces:
   ```bash
   kubectl label namespace mediaradar istio-injection=enabled
   ```

2. **Create Gateway and VirtualService** resources for your applications (see examples below)

3. **Access Kiali** to visualize your service mesh

## ARM64 Compatibility

All Istio images from version 1.23.2+ support ARM64 architecture natively. No special configuration needed.

## Troubleshooting

```bash
# Check istiod logs
kubectl logs -n istio-system -l app=istiod

# Check ingress gateway logs
kubectl logs -n istio-system -l app=istio-ingressgateway

# Analyze configuration
istioctl analyze -n mediaradar
```




