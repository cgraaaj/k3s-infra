#!/bin/bash

# Setup centralized registry access across all namespaces
# This adds imagePullSecrets to the default service account in each namespace

set -e

echo "🔐 Setting up centralized registry access"
echo "========================================"
echo ""

REGISTRY_SECRET_NAME="harbor-credentials"
DOCKERCONFIG_FILE="/home/cgraaaj/Projects/k3s-projects/argo-registry/dockerconfig.json"

# List of namespaces that need registry access
NAMESPACES=(
  "monitoring"
  "mediaradar"
  "mediaradar-svc"
  "stockx"
  "default"
  "argocd-qa"
)

# Create secret in each namespace
for ns in "${NAMESPACES[@]}"; do
  echo "📝 Configuring namespace: $ns"
  
  # Create namespace if it doesn't exist
  kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
  
  # Create/update the registry secret
  kubectl create secret generic $REGISTRY_SECRET_NAME \
    --from-file=.dockerconfigjson=$DOCKERCONFIG_FILE \
    --type=kubernetes.io/dockerconfigjson \
    --namespace=$ns \
    --dry-run=client -o yaml | kubectl apply -f -
  
  echo "  ✅ Secret created/updated in $ns"
  
  # Patch the default service account to use this secret
  kubectl patch serviceaccount default \
    -n $ns \
    -p "{\"imagePullSecrets\":[{\"name\":\"$REGISTRY_SECRET_NAME\"}]}" 2>/dev/null || \
  kubectl patch serviceaccount default \
    -n $ns \
    --type='json' \
    -p="[{\"op\":\"add\",\"path\":\"/imagePullSecrets\",\"value\":[{\"name\":\"$REGISTRY_SECRET_NAME\"}]}]"
  
  echo "  ✅ Default service account patched in $ns"
  echo ""
done

echo "========================================"
echo "✅ Centralized registry access configured!"
echo ""
echo "📊 Verification:"
for ns in "${NAMESPACES[@]}"; do
  echo "  Namespace: $ns"
  kubectl get serviceaccount default -n $ns -o jsonpath='{.imagePullSecrets[*].name}' 2>/dev/null && echo || echo "    No secrets configured"
done
echo ""
echo "🎯 Now ALL pods in these namespaces can pull from registry.cgraaaj.in"
echo ""
echo "🔄 Restart your alert-router:"
echo "   kubectl rollout restart deployment/alert-router -n monitoring"
echo ""




