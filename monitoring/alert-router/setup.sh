#!/bin/bash

# Setup Custom Alert Router with Discord

set -e

echo "🚀 Custom Alert Router Setup"
echo "============================="
echo ""

# Get Discord webhook URLs
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <critical-webhook> <warning-webhook> [info-webhook]"
    echo ""
    echo "Example:"
    echo "  $0 'https://discord.com/api/webhooks/xxx/critical' \\"
    echo "     'https://discord.com/api/webhooks/xxx/warning' \\"
    echo "     'https://discord.com/api/webhooks/xxx/info'"
    echo ""
    exit 1
fi

WEBHOOK_CRITICAL="$1"
WEBHOOK_WARNING="$2"
WEBHOOK_INFO="${3:-$WEBHOOK_WARNING}"  # Default to warning if not provided

echo "✅ Discord webhooks configured"
echo ""

# Create Discord webhooks secret
echo "📝 Creating Discord webhooks secret..."
kubectl create secret generic discord-webhooks \
  -n monitoring \
  --from-literal=critical="$WEBHOOK_CRITICAL" \
  --from-literal=warning="$WEBHOOK_WARNING" \
  --from-literal=info="$WEBHOOK_INFO" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Discord webhooks secret created"
echo ""

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

# Deploy alert router (assumes image is already built)
echo "🚀 Deploying alert router..."
kubectl apply -f "$SCRIPT_DIR/deployment.yaml"

# Wait for deployment
echo "⏳ Waiting for alert router to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/alert-router -n monitoring || true

echo "✅ Alert router deployed"
echo ""

# Deploy server down alerts
echo "📝 Deploying server down alert rules..."
kubectl apply -f "$PROJECT_ROOT/monitoring/alerts/server-down-alert.yaml"

echo "✅ Alert rules deployed"
echo ""

# Update Alertmanager configuration
echo "📝 Updating Alertmanager configuration..."
kubectl apply -f "$PROJECT_ROOT/monitoring/alertmanager-router-config.yaml"

# Restart Alertmanager
echo "🔄 Restarting Alertmanager..."
kubectl rollout restart statefulset/alertmanager-prometheus-alertmanager -n monitoring

echo "⏳ Waiting for Alertmanager to be ready..."
kubectl rollout status statefulset/alertmanager-prometheus-alertmanager -n monitoring --timeout=120s

echo "✅ Alertmanager restarted"
echo ""

echo "============================="
echo "✅ Setup complete!"
echo ""
echo "🎯 Architecture:"
echo "   Prometheus → Alertmanager → Alert Router → Discord"
echo "   Uptime Kuma → Alert Router → Discord"
echo ""
echo "📊 Alert Router endpoints:"
echo "   • /webhook/alertmanager - Receives from Alertmanager"
echo "   • /webhook/uptime-kuma - Receives from Uptime Kuma"
echo "   • /silences - Manage silence rules"
echo "   • /metrics - Router metrics"
echo "   • /health - Health check"
echo ""
echo "🔧 Configure Uptime Kuma (External Access):"
echo ""
echo "   📌 Option 1: Using NodePort (Simpler)"
echo "      kubectl apply -f $SCRIPT_DIR/service-nodeport.yaml"
echo "      URL: http://<any-k3s-node-ip>:30808/webhook/uptime-kuma"
echo "      Example: http://192.168.1.67:30808/webhook/uptime-kuma"
echo ""
echo "   📌 Option 2: Using Ingress (Production)"
echo "      1. Update DNS: alert-router.dev.cgraaaj.in → your cluster IP"
echo "      2. Create TLS cert (or use cert-manager)"
echo "      3. kubectl apply -f $SCRIPT_DIR/ingress.yaml"
echo "      URL: https://alert-router.dev.cgraaaj.in/webhook/uptime-kuma"
echo ""
echo "   Configure in Uptime Kuma:"
echo "      Settings → Notifications → Add New"
echo "      Type: Webhook"
echo "      Method: POST"
echo "      Content Type: application/json"
echo ""
echo "🔍 Test alert router:"
echo "   kubectl port-forward -n monitoring svc/alert-router 8080:8080"
echo "   curl http://localhost:8080/health"
echo ""
echo "📝 View logs:"
echo "   kubectl logs -n monitoring -l app=alert-router -f"
echo ""
echo "📊 Check metrics:"
echo "   kubectl port-forward -n monitoring svc/alert-router 8080:8080"
echo "   curl http://localhost:8080/metrics"
echo ""
echo "🎛️  Create a silence (example):"
echo '   curl -X POST http://localhost:8080/silences \\'
echo '     -H "Content-Type: application/json" \\'
echo '     -d {"name": "maintenance", "matchers": {"alertname": "ServerDown"}, "ends_at": "2024-12-31T23:59:59"}'
echo ""

