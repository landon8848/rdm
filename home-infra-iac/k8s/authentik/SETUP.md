# Authentik SSO — Setup Guide

> See also: [ADR-001](../../docs/adr/001-authentik-sso.md) for decision context.

## Prerequisites (in order)

### 1. Install CNPG operator (if not already installed)

See [k8s/cnpg/SETUP.md](../cnpg/SETUP.md). The operator must be running before Authentik's database cluster can be created.

```bash
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm install cnpg cnpg/cloudnative-pg \
  --namespace cnpg-system --create-namespace \
  --values k8s/cnpg/values.yaml --wait
```

### 2. Create Vault secrets

```bash
# Generate credentials
SECRET_KEY=$(openssl rand -hex 32)
BOOTSTRAP_TOKEN=$(openssl rand -base64 32)
BOOTSTRAP_PASS=$(openssl rand -base64 24)
DB_PASS=$(openssl rand -base64 24)

# Store admin credentials
vault kv put secret/authentik/admin \
  secret_key="$SECRET_KEY" \
  bootstrap_token="$BOOTSTRAP_TOKEN" \
  bootstrap_password="$BOOTSTRAP_PASS" \
  bootstrap_email="user@example.com"

# Store PostgreSQL credentials (CNPG expects 'username' + 'password' keys)
vault kv put secret/authentik/db \
  username="authentik" \
  password="$DB_PASS"
```

### 3. Create Vault policy and K8s auth role

```bash
vault policy write authentik - <<'EOF'
path "secret/data/authentik/*" {
  capabilities = ["read"]
}
path "secret/metadata/authentik/*" {
  capabilities = ["read"]
}
EOF

vault write auth/kubernetes/role/authentik \
  bound_service_account_names=vault-auth \
  bound_service_account_namespaces=authentik \
  policies=authentik \
  ttl=1h
```

### 4. DNS (no action needed)

`auth.example.com` is already covered by the Pi-hole dnsmasq wildcard
(`address=/.example.com/192.168.1.87`). No new record required —
any `*.example.com` subdomain automatically resolves to Traefik.

### 5. Git push (ArgoCD syncs config manifests)

```bash
git add k8s/authentik/ k8s/argocd/apps/authentik.yaml k8s/cnpg/ k8s/argocd/apps/cnpg.yaml docs/adr/
git commit -m "Add Authentik SSO with CNPG, Traefik ForwardAuth, Vault secrets, and ADR"
git push
```

ArgoCD will auto-sync `vaultauth.yaml`, `database.yaml`, `ingress.yaml`, and `middleware.yaml`.

### 6. Wait for CNPG database cluster to be ready

```bash
# The CNPG Cluster CRD is synced by ArgoCD. Wait for the database to bootstrap.
kubectl wait cluster authentik-db -n authentik \
  --for=condition=Ready --timeout=120s

# Verify the -rw service exists
kubectl get svc authentik-db-rw -n authentik
```

### 7. Install Authentik via Helm

```bash
helm repo add authentik https://charts.goauthentik.io
helm repo update

helm install authentik authentik/authentik \
  --namespace authentik \
  --values k8s/authentik/values.yaml \
  --wait --timeout 5m
```

### 8. Verify deployment

```bash
# Check all pods are running
kubectl get pods -n authentik

# Verify TLS certificate issued
kubectl get certificate authentik-tls -n authentik
kubectl wait certificate authentik-tls -n authentik --for=condition=Ready --timeout=120s

# Verify Vault secret sync
kubectl get vaultstaticsecret -n authentik
kubectl get secret authentik-admin-secret -n authentik
kubectl get secret authentik-db-secret -n authentik

# Verify CNPG cluster health
kubectl get cluster authentik-db -n authentik

# Check the ArgoCD app
kubectl get application authentik-config -n argocd
```

### 9. Access Authentik admin UI

Navigate to `https://auth.example.com/if/admin/`

Login with:
- **Username:** `akadmin`
- **Password:** the `bootstrap_password` value from step 2

---

## Post-Install: OIDC Provider Configuration

### Proxmox OIDC

1. In Authentik admin → **Applications** → **Create**:
   - Name: `Proxmox`
   - Slug: `proxmox`
   - Provider: Create new → **OAuth2/OpenID Provider**
     - Name: `proxmox`
     - Authorization flow: `default-authorization-flow (Authorize Application)`
     - Redirect URIs: `https://192.168.1.148:8006` (Proxmox host)
     - Signing key: select the auto-generated Authentik self-signed key
   - Note the **Client ID** and **Client Secret**

2. In Proxmox UI → **Datacenter** → **Realms** → **Add** → **OpenID Connect**:
   - Issuer URL: `https://auth.example.com/application/o/proxmox/`
   - Realm: `authentik`
   - Client ID: (from step 1)
   - Client Secret: (from step 1)
   - Default: No (keep PAM as default for emergency access)
   - Autocreate Users: Yes (or manually create `lando@authentik` with desired permissions)
   - Username Claim: `preferred_username`

3. Map Proxmox permissions:
   ```bash
   # On Proxmox host — grant admin to your Authentik user
   pveum user add lando@authentik
   pveum acl modify / --users lando@authentik --roles Administrator
   ```

### ArgoCD OIDC

1. In Authentik admin → **Applications** → **Create**:
   - Name: `ArgoCD`
   - Slug: `argocd`
   - Provider: Create new → **OAuth2/OpenID Provider**
     - Name: `argocd`
     - Redirect URIs: `https://argo.example.com/auth/callback`
     - Scopes: `openid`, `profile`, `email`
   - Note the **Client ID** and **Client Secret**

2. Store ArgoCD OIDC client secret in Vault:
   ```bash
   vault kv put secret/argocd/oidc \
     client_id="<client-id>" \
     client_secret="<client-secret>"
   ```

3. Update ArgoCD Helm values (`k8s/argocd/values.yaml`) to disable Dex and add OIDC:
   ```yaml
   configs:
     cm:
       dex.config: ""
       url: https://argo.example.com
       oidc.config: |
         name: Authentik
         issuer: https://auth.example.com/application/o/argocd/
         clientID: $argocd-oidc-secret:client_id
         clientSecret: $argocd-oidc-secret:client_secret
         requestedScopes:
           - openid
           - profile
           - email
     rbac:
       policy.csv: |
         g, authentik Admins, role:admin
   ```

4. Upgrade ArgoCD Helm release:
   ```bash
   helm upgrade argocd argo/argo-cd \
     --namespace argocd \
     --values k8s/argocd/values.yaml
   ```

### Traefik ForwardAuth (for apps like Mealie)

To protect any Traefik-fronted service, add the middleware reference to its IngressRoute:

1. In Authentik admin → **Applications** → **Create**:
   - Name: `Mealie` (or any app)
   - Provider: Create new → **Proxy Provider**
     - Mode: **Forward auth (single application)**
     - External host: `https://mealie.example.com`

2. Add the middleware to the app's IngressRoute:
   ```yaml
   spec:
     routes:
       - match: Host(`mealie.example.com`)
         kind: Rule
         middlewares:
           - name: authentik-forwardauth
             namespace: authentik
         services:
           - name: mealie
             port: 9000
   ```

Users hitting the app will be redirected to the Authentik login page, then sent back to the app after authentication. Authentik passes user identity via `X-authentik-*` response headers.

---

## Troubleshooting

**CNPG database not ready:** Check CNPG operator logs: `kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg`. Verify the `authentik-db-secret` exists with `username` and `password` keys: `kubectl get secret authentik-db-secret -n authentik -o jsonpath='{.data}'`.

**Outpost not starting:** The embedded outpost auto-creates after first login. If the `ak-outpost-authentik-embedded-outpost` service doesn't exist yet, log into the admin UI first.

**ForwardAuth 500 errors:** Verify the outpost service is running: `kubectl get svc -n authentik | grep outpost`. The middleware references the outpost by its cluster-internal DNS name.

**Certificate not ready:** Check cert-manager logs: `kubectl logs -n cert-manager -l app=cert-manager`. Ensure Pi-hole has the `auth.example.com` DNS record pointing to 192.168.1.87.
