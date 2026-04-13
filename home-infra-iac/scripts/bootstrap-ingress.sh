#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/my-k0s.config}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Helm repos ─────────────────────────────────────────────────────────────────
echo "==> Adding Helm repos"
helm repo add metallb https://metallb.github.io/metallb
helm repo add jetstack https://charts.jetstack.io
helm repo add traefik https://helm.traefik.io/traefik
helm repo update

# ── MetalLB ────────────────────────────────────────────────────────────────────
echo "==> Installing MetalLB"
helm upgrade --install metallb metallb/metallb \
  --namespace metallb-system \
  --create-namespace \
  --wait

echo "==> Applying MetalLB IP pool"
kubectl apply -f "$REPO_ROOT/k8s/metallb/ipaddresspool.yaml"

# ── cert-manager ───────────────────────────────────────────────────────────────
echo "==> Installing cert-manager"
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --wait

echo "==> Creating dns-provider API token secret"
if ! kubectl get secret dns-api-token -n cert-manager &>/dev/null; then
  if [[ -z "${DNS_API_TOKEN:-}" ]]; then
    echo "  DNS_API_TOKEN not set — skipping LE issuers (internal CA will still work)"
    echo "  Re-run with: DNS_API_TOKEN=<token> $0"
  else
    kubectl create secret generic dns-api-token \
      --from-literal=api-token="$DNS_API_TOKEN" \
      --namespace cert-manager
  fi
else
  echo "  Secret already exists, skipping"
fi

echo "==> Applying ClusterIssuers"
kubectl apply -f "$REPO_ROOT/k8s/cert-manager/clusterissuers.yaml"

echo "==> Waiting for internal CA cert to be ready"
kubectl wait certificate my-ca \
  --namespace cert-manager \
  --for=condition=Ready \
  --timeout=60s

# ── Traefik ────────────────────────────────────────────────────────────────────
echo "==> Installing Traefik"
helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace \
  --values "$REPO_ROOT/k8s/traefik/values.yaml" \
  --wait

echo "==> Applying Traefik dashboard IngressRoute"
kubectl apply -f "$REPO_ROOT/k8s/traefik/dashboard.yaml"

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo "==> Done. Traefik external IP:"
kubectl get svc -n traefik traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
echo ""
echo ""
echo "==> To trust the internal CA in your browser, export the CA cert:"
echo "    kubectl get secret my-ca-secret -n cert-manager -o jsonpath='{.data.tls\\.crt}' | base64 -d > my-ca.crt"
echo "    # Then add my-ca.crt to your OS/browser trust store"
