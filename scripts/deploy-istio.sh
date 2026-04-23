#!/bin/bash

# Istio Deployment Script for K3s ARM64 Cluster
# This script deploys Istio service mesh via ArgoCD

set -e

echo "🚀 Istio Deployment Script"
echo "=========================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl not found. Please install kubectl first."
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster. Check your kubeconfig."
    exit 1
fi

print_status "Connected to cluster"
echo ""

# Phase 1: Deploy Infrastructure Project
echo "📦 Phase 1: Creating Infrastructure AppProject"
echo "----------------------------------------------"
kubectl apply -f argo-registry/qa/manifests/projects/appproject-infrastructure.yaml
print_status "Infrastructure project created"
echo ""

sleep 2

# Phase 2: Deploy Istio Base (CRDs)
echo "📦 Phase 2: Deploying Istio Base (CRDs)"
echo "---------------------------------------"
kubectl apply -f argo-registry/qa/manifests/infra/istio-base.yaml
print_status "Istio Base application created"
echo ""

# Wait for Istio Base to sync
echo "⏳ Waiting for Istio Base to sync..."
kubectl wait --for=condition=Synced application/istio-base -n argocd-qa --timeout=300s 2>/dev/null || true
sleep 5

# Phase 3: Deploy Istiod (Control Plane)
echo "📦 Phase 3: Deploying Istiod (Control Plane)"
echo "--------------------------------------------"
kubectl apply -f argo-registry/qa/manifests/infra/istiod.yaml
print_status "Istiod application created"
echo ""

# Wait for Istiod to sync
echo "⏳ Waiting for Istiod to sync..."
kubectl wait --for=condition=Synced application/istiod -n argocd-qa --timeout=300s 2>/dev/null || true
sleep 5

# Phase 4: Deploy Istio Ingress Gateway
echo "📦 Phase 4: Deploying Istio Ingress Gateway"
echo "-------------------------------------------"
kubectl apply -f argo-registry/qa/manifests/infra/istio-ingressgateway.yaml
print_status "Istio Ingress Gateway application created"
echo ""

# Wait for Ingress Gateway to sync
echo "⏳ Waiting for Ingress Gateway to sync..."
kubectl wait --for=condition=Synced application/istio-ingressgateway -n argocd-qa --timeout=300s 2>/dev/null || true
sleep 5

# Phase 5: Deploy Prometheus
echo "📦 Phase 5: Deploying Prometheus"
echo "--------------------------------"
kubectl apply -f argo-registry/qa/manifests/infra/prometheus.yaml
print_status "Prometheus application created"
echo ""

# Phase 6: Deploy Kiali
echo "📦 Phase 6: Deploying Kiali Dashboard"
echo "-------------------------------------"
kubectl apply -f argo-registry/qa/manifests/infra/kiali.yaml
print_status "Kiali application created"
echo ""

# Wait for all applications
echo "⏳ Waiting for all applications to sync (this may take a few minutes)..."
echo ""

sleep 10

# Check application status
echo "📊 ArgoCD Application Status:"
echo "----------------------------"
kubectl get applications -n argocd-qa | grep -E "NAME|istio|prometheus|kiali"
echo ""

# Check pod status
echo "📊 Istio System Pods:"
echo "--------------------"
kubectl get pods -n istio-system 2>/dev/null || print_warning "istio-system namespace not ready yet"
echo ""

# Summary
echo ""
echo "======================================"
echo "✅ Istio Deployment Initiated!"
echo "======================================"
echo ""
echo "Next Steps:"
echo ""
echo "1. Monitor deployment progress:"
echo "   watch kubectl get applications -n argocd-qa"
echo ""
echo "2. Check Istio pods:"
echo "   kubectl get pods -n istio-system"
echo ""
echo "3. Verify Istio installation (once pods are running):"
echo "   istioctl proxy-status"
echo ""
echo "4. Access Kiali dashboard:"
echo "   kubectl get svc -n istio-system kiali-server"
echo "   kubectl port-forward -n istio-system svc/kiali-server 20001:20001"
echo "   Then open: http://localhost:20001/kiali"
echo ""
echo "5. Add Istio resources to your mediaradar app:"
echo "   See: examples/ISTIO-INTEGRATION-GUIDE.md"
echo ""
echo "📚 Full documentation: DEPLOYMENT-GUIDE.md"
echo ""

# Optional: Install istioctl
read -p "Do you want to install istioctl CLI? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "📥 Installing istioctl..."
    curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.23.2 sh -
    echo ""
    echo "To use istioctl, run:"
    echo "  cd istio-1.23.2"
    echo "  export PATH=\$PWD/bin:\$PATH"
    echo "  istioctl version"
fi

echo ""
print_status "Deployment complete! 🎉"




