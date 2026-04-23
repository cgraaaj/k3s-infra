#!/bin/bash

# Build and deploy custom alert router

set -e

echo "🔨 Building Custom Alert Router"
echo "================================"
echo ""

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Configuration
REGISTRY="registry.cgraaaj.in"  # Change this to your registry (e.g., harbor.dev.cgraaaj.in)
PROJECT="observability"
IMAGE_NAME="alert-router"
TAG="latest"
FULL_IMAGE="${REGISTRY}/${PROJECT}/${IMAGE_NAME}:${TAG}"

# Build multi-architecture Docker image
echo "📦 Building multi-architecture Docker image (amd64, arm64)..."
cd "$SCRIPT_DIR"

# Check if buildx builder exists, create if not
if ! docker buildx ls | grep -q "multiarch-builder"; then
  echo "📐 Creating buildx builder..."
  docker buildx create --name multiarch-builder --use
  docker buildx inspect --bootstrap
fi

# Use existing builder
docker buildx use multiarch-builder

# Build and push multi-arch image directly to your registry
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag ${FULL_IMAGE} \
  --push \
  .

echo ""
echo "✅ Multi-arch image built and pushed: ${FULL_IMAGE}"
echo "   Architectures: linux/amd64, linux/arm64"
echo ""

# Update deployment with correct image
echo "📝 Updating deployment manifest..."
sed -i "s|image: .*alert-router.*|image: ${FULL_IMAGE}|" "$SCRIPT_DIR/deployment.yaml"

# Apply Kubernetes manifests
echo "🚀 Deploying to Kubernetes..."
kubectl apply -f "$SCRIPT_DIR/deployment.yaml"

echo "✅ Alert router deployed"
echo ""

# Wait for deployment
echo "⏳ Waiting for pods to be ready..."
kubectl wait --for=condition=available --timeout=60s deployment/alert-router -n monitoring

echo "✅ Alert router is ready"
echo ""

echo "================================"
echo "✅ Custom Alert Router deployed!"
echo ""
echo "📊 Check status:"
echo "   kubectl get pods -n monitoring -l app=alert-router"
echo ""
echo "📝 View logs:"
echo "   kubectl logs -n monitoring -l app=alert-router -f"
echo ""
echo "🔍 Test endpoints:"
echo "   kubectl port-forward -n monitoring svc/alert-router 8080:8080"
echo "   curl http://localhost:8080/health"
echo "   curl http://localhost:8080/metrics"
echo ""

