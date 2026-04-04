#!/usr/bin/env bash
# Bootstrap Forgejo — stores admin credentials in Vault, installs via Helm.
# Usage: FORGEJO_ADMIN_PASSWORD=<password> ./scripts/bootstrap-forgejo.sh
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/rdm-k0s.config}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_HOST="192.168.1.191"
SSH_KEY="$HOME/.ssh/id_ed25519"
INIT_FILE="$REPO_ROOT/ansible/vault/vault-init.json"

if [[ -z "${FORGEJO_ADMIN_PASSWORD:-}" ]]; then
  echo "Error: FORGEJO_ADMIN_PASSWORD is not set"
  echo "Usage: FORGEJO_ADMIN_PASSWORD=<password> $0"
  exit 1
fi

ROOT_TOKEN="$(jq -r '.root_token' "$INIT_FILE")"

vault_cmd() {
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no myadmin@$VAULT_HOST \
    "VAULT_ADDR=https://127.0.0.1:8200 VAULT_SKIP_VERIFY=true VAULT_TOKEN=$ROOT_TOKEN vault $*"
}

# ── Vault: Store admin credentials ────────────────────────────────────────────
echo "==> Storing Forgejo admin credentials in Vault"
vault_cmd "kv put secret/forgejo/admin \
  username='myadmin' \
  password='$FORGEJO_ADMIN_PASSWORD' \
  email='user@example.com'"

# ── Vault: Policy + role ──────────────────────────────────────────────────────
echo "==> Writing Forgejo Vault policy"
vault_cmd "policy write forgejo-read - <<'EOF'
path \"secret/data/forgejo/*\" {
  capabilities = [\"read\"]
}
path \"secret/metadata/forgejo/*\" {
  capabilities = [\"read\"]
}
EOF"

echo "==> Creating Kubernetes auth role for Forgejo"
vault_cmd "write auth/kubernetes/role/forgejo \
  bound_service_account_names=vault-auth \
  bound_service_account_namespaces=forgejo \
  policies=forgejo-read \
  ttl=1h"

# ── Helm: Forgejo ─────────────────────────────────────────────────────────────
echo "==> Adding Gitea Helm repo"
helm repo add gitea-charts https://dl.gitea.com/charts/
helm repo update gitea-charts

echo "==> Installing Forgejo"
kubectl create namespace forgejo --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install forgejo gitea-charts/gitea \
  --namespace forgejo \
  --values "$REPO_ROOT/k8s/forgejo/values.yaml" \
  --wait --timeout 5m

# ── Kubernetes: VSO + Ingress ─────────────────────────────────────────────────
echo "==> Applying VaultAuth and admin secret sync"
kubectl apply -f "$REPO_ROOT/k8s/forgejo/vaultauth.yaml"

echo "==> Applying IngressRoute and TLS certificate"
kubectl apply -f "$REPO_ROOT/k8s/forgejo/ingress.yaml"

echo ""
echo "==> Waiting for TLS cert"
kubectl wait certificate forgejo-tls -n forgejo \
  --for=condition=Ready --timeout=120s

echo ""
echo "==> Done!"
echo "    Web UI: https://git.example.com"
echo "    SSH:    git@git.example.com:<user>/<repo>.git"
echo "    Login:  myadmin / <your password>"
