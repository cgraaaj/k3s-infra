#!/bin/bash
set -euo pipefail

# Syncs wildcard TLS secrets from cert-manager namespace to all app namespaces.
# Run this after cert renewal or when adding a new namespace.
#
# Usage:
#   ./sync-wildcard-secrets.sh              # sync all
#   ./sync-wildcard-secrets.sh <namespace>  # sync to a specific new namespace

MAIN_SECRET="wildcard-cgraaaj-in-tls"
DEV_SECRET="wildcard-dev-cgraaaj-in-tls"
SOURCE_NS="cert-manager"

MAIN_TARGETS=(argocd argocd-qa authentik coder hashicorpvault mediaradar monitoring stockx traefik)
DEV_TARGETS=(authentik istio-system monitoring stockx traefik)

copy_secret() {
  local secret_name=$1
  local target_ns=$2
  kubectl get secret "$secret_name" -n "$SOURCE_NS" -o json | \
    python3 -c "
import sys, json
s = json.load(sys.stdin)
s['metadata'] = {'name': s['metadata']['name'], 'namespace': '${target_ns}'}
json.dump(s, sys.stdout)
" | kubectl apply -f - 2>&1
}

if [ "${1:-}" != "" ]; then
  echo "Syncing to namespace: $1"
  copy_secret "$MAIN_SECRET" "$1"
  copy_secret "$DEV_SECRET" "$1"
  exit 0
fi

echo "=== Syncing $MAIN_SECRET ==="
for ns in "${MAIN_TARGETS[@]}"; do
  copy_secret "$MAIN_SECRET" "$ns"
done

echo ""
echo "=== Syncing $DEV_SECRET ==="
for ns in "${DEV_TARGETS[@]}"; do
  copy_secret "$DEV_SECRET" "$ns"
done

echo ""
echo "=== Verification ==="
kubectl get secrets --all-namespaces | grep wildcard
