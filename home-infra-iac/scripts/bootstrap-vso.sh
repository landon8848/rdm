#!/usr/bin/env bash
# Bootstrap Vault Secrets Operator integration.
# Usage: CLOUDFLARE_API_TOKEN=<token> ./scripts/bootstrap-vso.sh
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/rdm-k0s.config}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_HOST="192.168.1.191"
SSH_KEY="$HOME/.ssh/id_ed25519"
INIT_FILE="$REPO_ROOT/ansible/vault/vault-init.json"

if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  echo "Error: CLOUDFLARE_API_TOKEN is not set"
  echo "Usage: CLOUDFLARE_API_TOKEN=<token> $0"
  exit 1
fi

if [[ ! -f "$INIT_FILE" ]]; then
  echo "Error: $INIT_FILE not found — run the vault playbook first"
  exit 1
fi

ROOT_TOKEN="$(jq -r '.root_token' "$INIT_FILE")"

vault_cmd() {
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no myadmin@$VAULT_HOST \
    "VAULT_ADDR=https://127.0.0.1:8200 VAULT_SKIP_VERIFY=true VAULT_TOKEN=$ROOT_TOKEN vault $*"
}

# ── Vault: KV v2 ───────────────────────────────────────────────────────────────
echo "==> Enabling KV v2 secrets engine"
vault_cmd "secrets enable -path=secret kv-v2" 2>&1 || echo "  (already enabled)"

# ── Vault: Kubernetes auth ─────────────────────────────────────────────────────
echo "==> Enabling Kubernetes auth method"
vault_cmd "auth enable kubernetes" 2>&1 || echo "  (already enabled)"

echo "==> Configuring Kubernetes auth"
KUBE_HOST="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')"

# Create a dedicated SA for Vault's TokenReview calls (required when Vault runs outside k8s)
kubectl create serviceaccount vault-tokenreview -n kube-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create clusterrolebinding vault-tokenreview \
  --clusterrole=system:auth-delegator \
  --serviceaccount=kube-system:vault-tokenreview \
  --dry-run=client -o yaml | kubectl apply -f -
REVIEWER_JWT="$(kubectl create token vault-tokenreview -n kube-system --duration=8760h)"

# Copy CA cert as a file — inline embedding gets mangled by shell escaping
kubectl config view --minify --raw \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > /tmp/k8s-ca.crt
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no /tmp/k8s-ca.crt myadmin@$VAULT_HOST:/tmp/k8s-ca.crt
rm /tmp/k8s-ca.crt

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no myadmin@$VAULT_HOST \
  "VAULT_ADDR=https://127.0.0.1:8200 VAULT_SKIP_VERIFY=true VAULT_TOKEN=$ROOT_TOKEN \
   vault write auth/kubernetes/config \
     kubernetes_host=$KUBE_HOST \
     kubernetes_ca_cert=@/tmp/k8s-ca.crt \
     token_reviewer_jwt='$REVIEWER_JWT' && rm /tmp/k8s-ca.crt"

# ── Vault: Store Cloudflare token ──────────────────────────────────────────────
echo "==> Storing Cloudflare API token in Vault"
vault_cmd "kv put secret/cert-manager/cloudflare api-token='$CLOUDFLARE_API_TOKEN'"

# ── Vault: Policy ─────────────────────────────────────────────────────────────
echo "==> Writing cert-manager Vault policy"
vault_cmd "policy write cert-manager-read - <<'EOF'
path \"secret/data/cert-manager/*\" {
  capabilities = [\"read\"]
}
path \"secret/metadata/cert-manager/*\" {
  capabilities = [\"read\"]
}
EOF"

# ── Vault: Kubernetes auth role ────────────────────────────────────────────────
echo "==> Creating Kubernetes auth role for cert-manager"
vault_cmd "write auth/kubernetes/role/cert-manager \
  bound_service_account_names=vault-auth \
  bound_service_account_namespaces=cert-manager \
  policies=cert-manager-read \
  ttl=1h"

# ── Helm: VSO ─────────────────────────────────────────────────────────────────
echo "==> Adding HashiCorp Helm repo"
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

echo "==> Installing Vault Secrets Operator"
helm upgrade --install vault-secrets-operator hashicorp/vault-secrets-operator \
  --namespace vault-secrets-operator-system \
  --create-namespace \
  --values "$REPO_ROOT/k8s/vault-secrets-operator/values.yaml" \
  --wait

# ── Kubernetes: VaultAuth + VaultStaticSecret ─────────────────────────────────
echo "==> Applying VaultAuth for cert-manager"
kubectl apply -f "$REPO_ROOT/k8s/vault-secrets-operator/vaultauth.yaml"

echo "==> Applying VaultStaticSecret for Cloudflare token"
kubectl apply -f "$REPO_ROOT/k8s/cert-manager/cloudflare-secret.yaml"

echo ""
echo "==> Waiting for Cloudflare secret to sync"
sleep 5
kubectl get secret cloudflare-api-token -n cert-manager \
  -o jsonpath='{.data.api-token}' | base64 -d | grep -q . \
  && echo "  Secret synced successfully" \
  || echo "  Secret not yet synced — check: kubectl describe vaultstaticsecret -n cert-manager"
