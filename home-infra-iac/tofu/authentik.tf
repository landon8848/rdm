# ── Authentik SSO ────────────────────────────────────────────────────
# Manages OAuth2/OIDC providers and ForwardAuth proxy providers for all
# services that authenticate through Authentik.

# ── Data sources ────────────────────────────────────────────────────

data "authentik_flow" "default_authorization" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "default_invalidation" {
  slug = "default-provider-invalidation-flow"
}

data "authentik_certificate_key_pair" "default" {
  name = "authentik Self-signed Certificate"
}

data "authentik_property_mapping_provider_scope" "oauth2" {
  managed_list = [
    "goauthentik.io/providers/oauth2/scope-openid",
    "goauthentik.io/providers/oauth2/scope-profile",
    "goauthentik.io/providers/oauth2/scope-email",
  ]
}

# ── OIDC: Grafana ───────────────────────────────────────────────────

resource "authentik_provider_oauth2" "grafana" {
  name               = "Grafana"
  client_id          = "grafana"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  client_type        = "confidential"
  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://grafana.example.com/login/generic_oauth"
    },
  ]
  signing_key       = data.authentik_certificate_key_pair.default.id
  property_mappings = data.authentik_property_mapping_provider_scope.oauth2.ids
}

resource "authentik_application" "grafana" {
  name              = "Grafana"
  slug              = "grafana"
  protocol_provider = authentik_provider_oauth2.grafana.id
}

# ── OIDC: Forgejo ───────────────────────────────────────────────────

resource "authentik_provider_oauth2" "forgejo" {
  name               = "Forgejo"
  client_id          = "forgejo"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  client_type        = "confidential"
  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://git.example.com/user/oauth2/Authentik/callback"
    },
  ]
  signing_key       = data.authentik_certificate_key_pair.default.id
  property_mappings = data.authentik_property_mapping_provider_scope.oauth2.ids
}

resource "authentik_application" "forgejo" {
  name              = "Forgejo"
  slug              = "forgejo"
  protocol_provider = authentik_provider_oauth2.forgejo.id
}

# ── OIDC: Vault ─────────────────────────────────────────────────────

resource "authentik_provider_oauth2" "vault" {
  name               = "Vault"
  client_id          = "vault"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  client_type        = "confidential"
  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://192.168.1.140:8200/ui/vault/auth/oidc/oidc/callback"
    },
    {
      matching_mode = "strict"
      url           = "https://vault.example.com:8200/ui/vault/auth/oidc/oidc/callback"
    },
    {
      matching_mode = "strict"
      url           = "http://localhost:8250/oidc/callback"
    },
  ]
  signing_key       = data.authentik_certificate_key_pair.default.id
  property_mappings = data.authentik_property_mapping_provider_scope.oauth2.ids
}

resource "authentik_application" "vault" {
  name              = "Vault"
  slug              = "vault"
  protocol_provider = authentik_provider_oauth2.vault.id
}
