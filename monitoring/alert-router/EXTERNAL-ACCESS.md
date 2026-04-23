# External Access to Alert Router

Since Uptime Kuma runs on a separate RPi (outside the K3s cluster), it cannot access the internal service DNS name `alert-router.monitoring.svc.cluster.local`.

## Solution Options

### 🚀 Option 1: NodePort (Recommended for Internal Use)

**Best for**: Internal tools, no DNS/TLS needed

```bash
kubectl apply -f service-nodeport.yaml
```

This exposes the alert-router on port **30808** on **all K3s nodes**.

**Uptime Kuma Webhook URL**:
```
http://<any-k3s-node-ip>:30808/webhook/uptime-kuma
```

**Examples**:
- `http://192.168.1.67:30808/webhook/uptime-kuma` (pudge)
- `http://192.168.1.68:30808/webhook/uptime-kuma` (crystalmaiden)
- `http://192.168.1.69:30808/webhook/uptime-kuma` (mirana)
- etc.

### 🌐 Option 2: Ingress with TLS (Production)

**Best for**: Production, proper DNS, HTTPS

1. **Update DNS** to point to your cluster:
   ```
   alert-router.dev.cgraaaj.in → <ingress-ip>
   ```

2. **Create TLS certificate** (if not using cert-manager):
   ```bash
   kubectl create secret tls alert-router-dev-cgraaaj-in-tls \
     --cert=path/to/cert.crt \
     --key=path/to/cert.key \
     -n monitoring
   ```

3. **Apply the Ingress**:
   ```bash
   kubectl apply -f ingress.yaml
   ```

**Uptime Kuma Webhook URL**:
```
https://alert-router.dev.cgraaaj.in/webhook/uptime-kuma
```

---

## 🔧 Configure Uptime Kuma

1. Open Uptime Kuma web interface
2. Go to **Settings** → **Notifications**
3. Click **Add New Notification**
4. Configure:
   - **Type**: Webhook
   - **URL**: Choose from Option 1 or Option 2 above
   - **Method**: POST
   - **Content Type**: application/json
5. Click **Test** to verify
6. **Save**

---

## 📊 Test the Webhook

### From your Uptime Kuma host:

**NodePort**:
```bash
curl -X POST http://192.168.1.67:30808/webhook/uptime-kuma \
  -H "Content-Type: application/json" \
  -d '{
    "heartbeat": {
      "status": 1,
      "msg": "Test alert"
    },
    "monitor": {
      "name": "Test Monitor"
    }
  }'
```

**Ingress**:
```bash
curl -X POST https://alert-router.dev.cgraaaj.in/webhook/uptime-kuma \
  -H "Content-Type: application/json" \
  -d '{
    "heartbeat": {
      "status": 1,
      "msg": "Test alert"
    },
    "monitor": {
      "name": "Test Monitor"
    }
  }'
```

---

## 🔍 Troubleshooting

### Check service is running:
```bash
kubectl get pods -n monitoring -l app=alert-router
kubectl get svc -n monitoring alert-router
```

### Check NodePort is accessible:
```bash
# From Uptime Kuma host
curl http://192.168.1.67:30808/health
```

### Check logs:
```bash
kubectl logs -n monitoring -l app=alert-router -f
```

### Verify routing from Alertmanager (internal):
```bash
kubectl run -it --rm curl --image=curlimages/curl --restart=Never -- \
  curl -v http://alert-router.monitoring.svc.cluster.local:8080/health
```



