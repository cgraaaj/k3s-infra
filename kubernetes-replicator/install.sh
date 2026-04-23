#!/bin/bash
set -euo pipefail

# kubernetes-replicator - Replicates Secrets & ConfigMaps across namespaces
# https://github.com/mittwald/kubernetes-replicator

NAMESPACE="kubernetes-replicator"

echo "=== Installing kubernetes-replicator ==="

helm repo add mittwald https://helm.mittwald.de
helm repo update

helm upgrade --install kubernetes-replicator mittwald/kubernetes-replicator \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --wait

echo ""
echo "=== kubernetes-replicator installed successfully ==="
echo ""
echo "Next steps:"
echo "  1. Apply wildcard certificates:"
echo "     kubectl apply -f cert-manager/certificates/production/wildcard.cgraaaj.in.yaml"
echo "     kubectl apply -f cert-manager/certificates/production/wildcard.dev.cgraaaj.in.yaml"
echo ""
echo "  2. Verify secrets are created in cert-manager namespace:"
echo "     kubectl get secrets -n cert-manager | grep wildcard"
echo ""
echo "  3. Verify replication to app namespaces:"
echo "     kubectl get secrets --all-namespaces | grep wildcard"
echo ""
echo "  4. Apply updated ingress files (they now reference wildcard secrets)"
echo ""
echo "=== Rollback ==="
echo "  If anything goes wrong:"
echo "     git checkout -- argocd/ authentik/ coder/ hashicorpvault/ jenkins/ monitoring/ traefik/"
echo "     kubectl apply -f cert-manager/certificates/production/  # re-apply old individual certs"
echo "     # Old TLS secrets still exist in each namespace until explicitly deleted"
