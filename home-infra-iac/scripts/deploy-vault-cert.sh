#!/usr/bin/env bash
# Issues (or redeploys a renewed) TLS cert for Vault from cert-manager,
# deploys it to the Vault VM, and updates VSO to trust the internal CA.
# Safe to re-run — cert-manager won't re-issue until renewBefore window.
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/my-k0s.config}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_HOST="192.168.1.140"
SSH_KEY="$HOME/.ssh/id_ed25519"

# ── Issue cert via cert-manager ────────────────────────────────────────────────
echo "==> Applying Vault TLS certificate request"
kubectl apply -f "$REPO_ROOT/k8s/vault/cert.yaml"

echo "==> Waiting for cert to be issued"
kubectl wait certificate vault-tls \
  --namespace cert-manager \
  --for=condition=Ready \
  --timeout=60s

# ── Extract cert + key from the Secret ────────────────────────────────────────
echo "==> Extracting cert and key"
kubectl get secret vault-tls -n cert-manager \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/vault-new.crt
kubectl get secret vault-tls -n cert-manager \
  -o jsonpath='{.data.tls\.key}' | base64 -d > /tmp/vault-new.key

# ── Deploy to Vault VM ─────────────────────────────────────────────────────────
echo "==> Deploying cert to Vault VM"
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
  /tmp/vault-new.crt myadmin@$VAULT_HOST:/tmp/vault.crt
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
  /tmp/vault-new.key myadmin@$VAULT_HOST:/tmp/vault.key

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no myadmin@$VAULT_HOST "
  sudo cp /tmp/vault.crt /opt/vault/tls/vault.crt
  sudo cp /tmp/vault.key /opt/vault/tls/vault.key
  sudo chown vault:vault /opt/vault/tls/vault.crt /opt/vault/tls/vault.key
  sudo chmod 640 /opt/vault/tls/vault.crt /opt/vault/tls/vault.key
  rm /tmp/vault.crt /tmp/vault.key
  sudo systemctl reload-or-restart vault
"
rm /tmp/vault-new.crt /tmp/vault-new.key

echo "==> Waiting for Vault to come back"
sleep 5

# ── Update VSO to trust the internal CA ───────────────────────────────────────
echo "==> Creating CA cert secret for VSO"
kubectl get secret my-ca-secret -n cert-manager \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/my-ca.crt

kubectl create secret generic vault-ca-cert \
  --from-file=ca.crt=/tmp/my-ca.crt \
  --namespace vault-secrets-operator-system \
  --dry-run=client -o yaml | kubectl apply -f -

rm /tmp/my-ca.crt

echo "==> Patching VaultConnection to use CA cert"
kubectl patch vaultconnection default -n vault-secrets-operator-system \
  --type=merge -p '{"spec":{"skipTLSVerify":false,"caCertSecretRef":"vault-ca-cert"}}'

echo ""
echo "==> Done. Verifying VSO sync still works"
sleep 5
kubectl get vaultstaticsecret -n cert-manager 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
