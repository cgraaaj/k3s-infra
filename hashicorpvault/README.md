# HashiCorp Vault

Bootstrap notes for the Vault instance deployed via the
[`hashicorpvault` ArgoCD Application](../argo-registry/qa/manifests/infra/hashicorpvault.yaml).

## Initial unseal

```bash
vault operator init
# Save the 5 unseal keys and the root token in a password manager.

vault operator unseal   # run 3 times with different keys
```

## Enable KV v2 and seed secrets

```bash
vault secrets enable kv-v2
# Create the required KV paths (e.g., kv-v2/data/mediaradar/api-keys).
```

## Policies

### `mediaradar-svc-policy`

```hcl
path "kv-v2/data/mediaradar/api-keys" {
  capabilities = ["read"]
}
```

Apply:

```bash
vault policy write mediaradar-svc-policy - <<EOF
path "kv-v2/data/mediaradar/api-keys" {
  capabilities = ["read"]
}
EOF
```

## Kubernetes auth method

```bash
vault auth enable kubernetes
vault write auth/kubernetes/config \
  kubernetes_host="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT"
```

## Database secrets engine (Redis example)

> IP post-migration: Redis is reachable at `10.19.94.72:6379`.

```bash
vault write database/config/redis \
  plugin_name="redis-database-plugin" \
  host="10.19.94.72" \
  port="6379" \
  tls="false" \
  username="cgraaaj" \
  password="cgraaaj@redis" \
  allowed_roles="redis-readonly"

vault write database/roles/redis-readonly \
  db_name="redis" \
  creation_statements='["on", "~*", "+@read", "+@connection"]' \
  revocation_statements='["ACL DELUSER {{name}}"]' \
  default_ttl="5m" \
  max_ttl="1h"

vault policy write redis-dynamic-creds-read - <<EOF
path "database/creds/redis-readonly" {
  capabilities = ["read"]
}
EOF
```

## Bind a Kubernetes SA to a role

```bash
vault write auth/kubernetes/role/mediaradar-svc-role \
  bound_service_account_names=mediaradar-svc-sa \
  bound_service_account_namespaces=mediaradar-svc \
  policies=mediaradar-svc-policy,redis-dynamic-creds-read \
  ttl=1h
```
