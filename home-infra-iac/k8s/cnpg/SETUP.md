# CloudNativePG Operator — Setup Guide

The CNPG operator manages PostgreSQL clusters declaratively via `Cluster` CRDs. The operator itself lives in `cnpg-system`; individual database clusters live in their application namespaces (e.g., `authentik`, `mealie`).

## Install the operator

```bash
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update

helm install cnpg cnpg/cloudnative-pg \
  --namespace cnpg-system --create-namespace \
  --values k8s/cnpg/values.yaml --wait
```

## Verify

```bash
kubectl get pods -n cnpg-system
kubectl get crds | grep cnpg
# Should see: clusters.postgresql.cnpg.io, backups.postgresql.cnpg.io, etc.
```

## Creating database clusters

Each application that needs PostgreSQL creates a `Cluster` CRD in its own namespace. See `k8s/authentik/database.yaml` for the first example.

The pattern:
1. Store the database superuser password in Vault at `secret/<app>/db`
2. Sync it into the namespace via VSO as a `kubernetes.io/basic-auth` Secret
3. Create a `Cluster` CRD referencing that Secret for `superuserSecret`
4. CNPG provisions the PostgreSQL instance with the specified credentials
5. The application connects via `<cluster-name>-rw.<namespace>.svc.cluster.local:5432`

## Monitoring

The operator exposes Prometheus metrics via PodMonitor. If kube-prometheus-stack is running, metrics are scraped automatically.

```bash
# Check operator metrics
kubectl get podmonitor -n cnpg-system
```
