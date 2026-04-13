# ADR-001: Authentik for Single Sign-On

**Status:** Proposed
**Date:** 2026-04-12
**Deciders:** Lando

## Context

The my-local homelab is expanding beyond single-user infrastructure services (ArgoCD, Traefik, Vault) into shared household applications (Mealie, Plex, Immich). Each new user-facing service introduces another set of credentials that household members must manage independently. Without centralized identity, onboarding a non-technical user (e.g., a spouse) means creating and communicating separate accounts per service, with no shared password policy, no MFA, and no self-service recovery.

The current ingress layer (Traefik v3 with cert-manager TLS) has no authentication middleware — every service is either open behind its own login page or accessible to anyone on the home network. Additionally, administrative surfaces like Proxmox, ArgoCD, and Grafana each maintain isolated user stores.

### Forces

- Household users should have one identity across all services.
- The solution must integrate with Traefik ForwardAuth for apps that lack native SSO support.
- Proxmox and ArgoCD both support OIDC natively and would benefit from delegated auth.
- Operational overhead must be reasonable for a single-operator homelab.
- The homelab doubles as a skills-building environment, but the operator already manages Keycloak professionally and prefers a lighter alternative.

## Decision

Adopt **Authentik** as the centralized identity provider for all homelab services, deployed as a Helm release in the `authentik` namespace on the k0s cluster.

## Options Considered

### Option A: Authelia

| Dimension | Assessment |
|-----------|------------|
| Complexity | Low |
| Resource cost | ~50 MB RAM |
| Protocol support | ForwardAuth headers only |
| Team familiarity | New |

**Pros:** Minimal footprint, native Traefik ForwardAuth support, YAML-driven config, single Go binary.
**Cons:** Not a real IdP — no OIDC/SAML provider, so apps like ArgoCD and Proxmox can't delegate auth. File-based user store means no self-service password reset without LDAP. Would need a separate OIDC provider later if requirements grow.

### Option B: Authentik

| Dimension | Assessment |
|-----------|------------|
| Complexity | Medium |
| Resource cost | ~400–600 MB RAM (server + PostgreSQL + Redis + outpost) |
| Protocol support | OIDC, SAML 2.0, LDAP, ForwardAuth proxy |
| Team familiarity | New |

**Pros:** Full identity provider with OIDC/SAML for native integration with Proxmox, ArgoCD, Grafana. Traefik ForwardAuth via proxy outpost for apps without native SSO. Modern admin UI. Self-service password resets and enrollment flows — critical for non-technical household users. Designed for the self-hosted/homelab community. Active development and community.
**Cons:** Heavier resource footprint than Authelia. Requires PostgreSQL and Redis. More components to manage (server, worker, outpost).

### Option C: Keycloak

| Dimension | Assessment |
|-----------|------------|
| Complexity | High |
| Resource cost | ~512 MB–1 GB RAM (Quarkus + PostgreSQL) |
| Protocol support | OIDC, SAML 2.0, LDAP, Kerberos |
| Team familiarity | High (operator uses it professionally) |

**Pros:** Enterprise-grade, extremely mature, full protocol support, fine-grained RBAC, identity brokering.
**Cons:** Resource-heavy Java application. Massive configuration surface area disproportionate to a 2-user household. No native Traefik ForwardAuth — requires OAuth2 Proxy sidecar per service. Operator explicitly prefers not to run it at home after managing it at work.

## Trade-off Analysis

The core trade-off is between Authelia's simplicity and Authentik's capability. Authelia would cover ForwardAuth for web apps immediately, but the moment we need OIDC for Proxmox or ArgoCD, we'd either bolt on a second system or migrate entirely. Authentik handles both use cases from day one at a moderate resource cost (~400–600 MB total across all components). Given that the integration targets include Proxmox OIDC, ArgoCD OIDC, and Traefik ForwardAuth, Authentik is the only single-system solution that covers all three.

Keycloak was eliminated on operational grounds — the operator manages it professionally and wants a lighter experience at home. Technically capable but disproportionate to the use case.

## Consequences

### What becomes easier
- Onboarding household members to new services (single account, one login page).
- Adding ForwardAuth to any new Traefik-fronted service (reference shared middleware).
- Proxmox and ArgoCD get proper delegated auth with user-level RBAC via OIDC.
- Self-service password resets for non-technical users without operator intervention.
- Future services that support OIDC (Gitea/Forgejo, Grafana, Immich) get SSO for free.

### What becomes harder
- PostgreSQL (via CNPG) and Redis become dependencies that need monitoring and backup. CNPG provides Prometheus metrics and PodMonitor integration.
- Authentik itself becomes a critical path — if it's down, ForwardAuth-gated services are inaccessible.
- Outpost configuration adds a layer of abstraction between Traefik and backend services.
- CNPG operator is a new cluster-wide component to maintain, though it's lightweight and adds value for every future service needing PostgreSQL.

### What we'll need to revisit
- Database backups: CNPG supports automated backups to object storage (Barman). Evaluate adding a MinIO instance or external S3-compatible target for scheduled PostgreSQL backups.
- Whether to OIDC-integrate Forgejo (currently using local admin auth).
- Whether to OIDC-integrate Grafana (currently using Vault-synced admin password).

## Integration Plan

### Day-one integrations
1. **Traefik ForwardAuth** — Authentik proxy outpost as middleware for apps without native SSO (Mealie, qBittorrent, Plex dashboard).
2. **Proxmox OIDC** — OAuth2/OIDC provider in Authentik, OpenID Connect realm in Proxmox Datacenter → Realms.
3. **ArgoCD OIDC** — OIDC provider in Authentik, ArgoCD `--dex-server` disabled, direct OIDC config in argocd-cm ConfigMap.

### Infrastructure requirements
- **CloudNativePG operator** in `cnpg-system` namespace — manages PostgreSQL clusters declaratively. Authentik's database is a `Cluster` CRD in the `authentik` namespace (`k8s/authentik/database.yaml`). Future services (Mealie, Immich) will each get their own `Cluster` CRD in their respective namespaces.
- Vault secrets: `secret/authentik/admin` (bootstrap token, secret key), `secret/authentik/db` (PostgreSQL credentials as `username` + `password` for CNPG `kubernetes.io/basic-auth` format).
- Vault policy + K8s auth role for `authentik` namespace.
- DNS: `auth.example.com` already resolved by Pi-hole dnsmasq wildcard (`*.example.com` → 192.168.1.87). No new record needed.
- TLS: Let's Encrypt cert via `letsencrypt-prod` ClusterIssuer (Authentik login page should be trusted by all devices).

## Action Items

1. [ ] Install CNPG operator (`helm install` with `k8s/cnpg/values.yaml`)
2. [ ] Create Vault secrets (`secret/authentik/admin`, `secret/authentik/db`)
3. [ ] Create Vault policy and K8s auth role for `authentik` namespace
4. [ ] Git push (ArgoCD syncs CNPG Cluster CRD + Authentik config manifests)
6. [ ] Wait for CNPG database cluster to be Ready
7. [ ] `helm install` Authentik with `k8s/authentik/values.yaml`
8. [ ] Configure Authentik: create admin user, OIDC providers, proxy outpost
9. [ ] Wire Proxmox OIDC realm to Authentik provider
10. [ ] Update ArgoCD Helm values for OIDC (disable Dex, add OIDC config)
11. [ ] Test ForwardAuth on a service (Mealie) before rolling out to others
