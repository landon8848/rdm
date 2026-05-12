# ── Vault: SSO credentials & policies ────────────────────────────────
# Stores Authentik OAuth2 client credentials in Vault KV and manages
# the policies that let VSO sync them into Kubernetes secrets.
# Also configures Vault's own OIDC auth method for UI/CLI login.

# ── Vault OIDC auth (login to Vault via Authentik) ──────────────────

resource "vault_jwt_auth_backend" "oidc" {
  description            = "Authentik OIDC"
  path                   = "oidc"
  type                   = "oidc"
  oidc_discovery_url     = "https://auth.example.com/application/o/vault/"
  oidc_discovery_ca_pem  = file("${path.module}/authentik-ca.pem")
  oidc_client_id         = authentik_provider_oauth2.vault.client_id
  oidc_client_secret     = authentik_provider_oauth2.vault.client_secret
  default_role           = "authentik"

  tune {
    default_lease_ttl = "1h"
    max_lease_ttl     = "24h"
    listing_visibility = "unauth"
    token_type         = "default-service"
  }
}

resource "vault_jwt_auth_backend_role" "authentik" {
  backend        = vault_jwt_auth_backend.oidc.path
  role_name      = "authentik"
  role_type      = "oidc"
  user_claim     = "sub"
  groups_claim   = "groups"
  token_policies = ["default"]
  token_ttl      = 3600
  token_max_ttl  = 86400

  allowed_redirect_uris = [
    "https://192.168.1.140:8200/ui/vault/auth/oidc/oidc/callback",
    "https://vault.example.com:8200/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback",
  ]

  oidc_scopes = ["openid", "profile", "email"]

  bound_claims = {
    groups = "authentik Admins"
  }
}

# Grant authentik Admins full admin access to Vault
resource "vault_identity_group" "admins" {
  name     = "authentik-admins"
  type     = "external"
  policies = ["admin-policy"]
}

resource "vault_policy" "admin_policy" {
  name = "admin-policy"

  policy = <<-EOT
    path "*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }
  EOT
}

resource "vault_identity_group_alias" "admins" {
  name           = "authentik Admins"
  mount_accessor = vault_jwt_auth_backend.oidc.accessor
  canonical_id   = vault_identity_group.admins.id
}

# ── Grafana OIDC credentials ────────────────────────────────────────

resource "vault_kv_secret_v2" "grafana_oidc" {
  mount = "secret"
  name  = "authentik/providers/grafana"

  data_json = jsonencode({
    client_id     = authentik_provider_oauth2.grafana.client_id
    client_secret = authentik_provider_oauth2.grafana.client_secret
  })
}

resource "vault_policy" "grafana" {
  name = "grafana"

  policy = <<-EOT
    path "secret/data/grafana/admin" {
      capabilities = ["read"]
    }
    path "secret/data/authentik/providers/grafana" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "grafana" {
  backend                          = "kubernetes"
  role_name                        = "grafana"
  bound_service_account_names      = ["vault-auth"]
  bound_service_account_namespaces = ["monitoring"]
  token_policies                   = ["grafana"]
  token_ttl                        = 3600
}

# ── Forgejo OIDC credentials ────────────────────────────────────────

resource "vault_kv_secret_v2" "forgejo_oidc" {
  mount = "secret"
  name  = "authentik/providers/forgejo"

  # Forgejo Helm chart expects 'key' and 'secret' field names
  data_json = jsonencode({
    key    = authentik_provider_oauth2.forgejo.client_id
    secret = authentik_provider_oauth2.forgejo.client_secret
  })
}

resource "vault_policy" "forgejo" {
  name = "forgejo"

  policy = <<-EOT
    path "secret/data/forgejo/admin" {
      capabilities = ["read"]
    }
    path "secret/data/authentik/providers/forgejo" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "forgejo" {
  backend                          = "kubernetes"
  role_name                        = "forgejo"
  bound_service_account_names      = ["vault-auth"]
  bound_service_account_namespaces = ["forgejo"]
  token_policies                   = ["forgejo"]
  token_ttl                        = 3600
}
