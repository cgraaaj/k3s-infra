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

## Database secrets engine (Redis)

> Redis is reachable at `10.19.94.72:6379` (Redis 7.4.x, standalone, ACL-enabled).

### Plugin caveat — Redis 7 / RESP3

Vault's bundled `redis-database-plugin` (as of Vault 1.21.x) speaks RESP2.
Redis 7 replies to `ACL SETUSER` (used by rotation) with RESP3 `blob-string`,
which the plugin cannot parse. Failure looks like:

```
unable to rotate credentials in periodic function: database=redis role=...
error="error setting credentials: reset of passwords for user X failed in
changeUserPassword: response returned from Conn:
expected prefix \"array\", got \"blob-string\""
```

Mitigation (must be applied **once** to the `database/config/redis` mount):

```bash
# Pin the connection to RESP2. Both keys are accepted by the upstream
# plugin starting with Vault 1.16; older versions silently ignore the
# extra fields and remain broken — upgrade Vault first if rotation still
# fails after applying this.
vault write database/config/redis \
  plugin_name=redis-database-plugin \
  host=10.19.94.72 \
  port=6379 \
  tls=false \
  username=cgraaaj \
  password='cgraaaj@redis' \
  protocol_version=2 \
  allowed_roles='redis-*'
```

### Dynamic role (short-TTL credentials)

```bash
vault write database/roles/redis-readonly \
  db_name=redis \
  creation_statements='["on", "~*", "+@read", "+@connection"]' \
  revocation_statements='["ACL DELUSER {{name}}"]' \
  default_ttl=5m \
  max_ttl=1h
```

### Static role (used by `mediaradar-svc`)

The static role keeps a fixed username (`mediaradar-svc-app`) and rotates the
password every 24h. The application reads the password from
`/vault/secrets/creds.env`, hot-reloads on file change (see
`media-radar-svc/config/database.js`) and never has to restart for a rotation
when everything is healthy.

```bash
# 1. Pre-create the user in Redis (Vault won't create users for static roles)
redis-cli -h 10.19.94.72 -p 6379 --user cgraaaj -a 'cgraaaj@redis' \
  ACL SETUSER mediaradar-svc-app on '>placeholder-will-be-rotated' \
      '~*' '&*' '+@all' '-@dangerous' '-@admin'
redis-cli -h 10.19.94.72 -p 6379 --user cgraaaj -a 'cgraaaj@redis' ACL SAVE

# 2. Tell Vault about it
vault write database/static-roles/redis-mediaradar-svc \
  db_name=redis \
  username=mediaradar-svc-app \
  rotation_statements='["ACL SETUSER {{username}} on >{{password}}"]' \
  rotation_period=86400

# 3. Trigger first rotation so Vault and Redis agree on the password
vault write -force database/rotate-role/redis-mediaradar-svc

# 4. Policy + Kubernetes auth role
vault policy write redis-static-creds-read-mediaradar-svc - <<EOF
path "database/static-creds/redis-mediaradar-svc" { capabilities = ["read"] }
EOF

vault write auth/kubernetes/role/mediaradar-svc-role \
  bound_service_account_names=mediaradar-svc-sa \
  bound_service_account_namespaces=mediaradar-svc \
  policies=mediaradar-svc-policy,redis-static-creds-read-mediaradar-svc \
  ttl=86400
```

> `ttl=86400` on the K8s role MUST be **>=** the static-role `rotation_period`,
> otherwise the agent token expires mid-rotation and the next render hangs.

## Recovering from `WRONGPASS` on `mediaradar-svc`

Symptoms: pod logs show `Redis Client Error: WRONGPASS invalid username-password
pair or user is disabled.` repeatedly, even after a pod restart.

Diagnosis order (do them in sequence):

```bash
# A. Are Vault and Redis seeing the same user?
redis-cli -h 10.19.94.72 -p 6379 --user cgraaaj -a 'cgraaaj@redis' ACL USERS
# Expected: includes 'mediaradar-svc-app'. If not -> recreate (step C).

# B. What does Vault think the password is?
VTOK=$(kubectl exec -n mediaradar-svc deploy/mediaradar-svc-k8s -c vault-agent \
        -- cat /home/vault/.vault-token)
kubectl exec -n hashicorpvault hashicorpvault-0 -- sh -c \
  "VAULT_TOKEN=$VTOK vault read database/static-creds/redis-mediaradar-svc"

# C. If the user is missing or out of sync, re-create with Vault's password
PASS=$(... step B, password field ...)
redis-cli -h 10.19.94.72 -p 6379 --user cgraaaj -a 'cgraaaj@redis' \
  ACL SETUSER mediaradar-svc-app on ">$PASS" '~*' '&*' '+@all' \
      '-@dangerous' '-@admin'
redis-cli -h 10.19.94.72 -p 6379 --user cgraaaj -a 'cgraaaj@redis' ACL SAVE

# D. Force a clean rotation through Vault so plugin state matches Redis
kubectl exec -n hashicorpvault hashicorpvault-0 -- sh -c \
  "VAULT_TOKEN=<root-or-admin-token> vault write -force \
    database/rotate-role/redis-mediaradar-svc"

# E. The Vault agent re-renders /vault/secrets/creds.env automatically; the
#    app's fs.watchFile picks it up within ~2s and reconnects. NO POD RESTART
#    NEEDED. If the app is on an image older than 8be3c76, restart it once:
kubectl rollout restart deploy/mediaradar-svc-k8s -n mediaradar-svc
```

The recurring nature of this incident before May 2026 was a 3-layer compound
failure documented in `docs/runbooks/mediaradar-svc-redis-wrongpass.md`. The
permanent fixes are:

1. `protocol_version=2` on `database/config/redis` (this file, above)
2. `redis-acl-saver` CronJob in this directory — periodically `ACL SAVE` so
   manually-recreated users survive a Redis restart
3. `media-radar-svc >= 8be3c76` — Node.js client now watches the creds file
   and reconnects on rotation (no more pod restart needed)
4. Prometheus alert `MediaradarSvcRedisCredsDrift` in
   `monitoring/alerts/vault-redis-rotation.yaml` — fires within 10 minutes of
   a rotation drift so we never discover this from user complaints again

### Known limitation: Vault Agent does NOT re-render mid-rotation

When a static-creds password is rotated, the in-pod Vault Agent template
**does not** re-render `/vault/secrets/creds.env` until either (a) the pod
restarts, or (b) the secret's lease expires (lease ≈ `rotation_period`,
i.e. 24h). `template-static-secret-render-interval` is set on the pod but
upstream Vault Agent currently classifies `database/static-creds/*` as a
"leased non-renewable" secret and skips the static interval poll — see
hashicorp/vault#19287 and #20805.

Why this is **not** an outage today:

- Established Redis TCP connections are NOT re-authenticated by Redis.
  The running app keeps working with its old (Vault-issued) password
  until the connection drops.
- `vault-redis-creds-verifier` runs every 5 minutes against Vault's
  CURRENT password and pages within 10 minutes if Vault and Redis ever
  diverge. If the running pod is using a stale-but-valid password,
  Redis is the source of truth and the verifier passes.
- If the running pod's connection drops AND it has stale creds, the
  app's reconnect (see `database.js`) loops with backoff and emits
  `WRONGPASS` log lines, which surface in `Redis Client Error:` count
  and trigger restart on the next deploy.

If you must propagate a rotation immediately, restart the pod:

```bash
kubectl rollout restart deploy/mediaradar-svc-k8s -n mediaradar-svc
```

Permanent fix when the upstream bug is resolved: drop the
`template-static-secret-render-interval` annotation override.
