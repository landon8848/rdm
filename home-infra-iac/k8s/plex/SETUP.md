# Plex Setup — Prerequisites

Plex shares the NFS media volume from `nfs-01` (192.168.1.125) with qBittorrent.
The NFS LXC must be set up first — see `k8s/qbittorrent/SETUP.md` steps 1–2.

## 1. Get a Plex Claim Token

Claim tokens link a new Plex server to your Plex account. They expire after
4 minutes, so generate this right before deploying.

1. Go to https://plex.tv/claim
2. Copy the token (starts with `claim-`)

## 2. Store the Claim Token in Vault

```bash
vault kv put secret/plex/claim \
  PLEX_CLAIM="claim-xxxxxxxxxxxxxxxxxxxx"
```

Create the Vault policy and Kubernetes auth role:

```bash
# Write policy
vault policy write plex - <<EOF
path "secret/data/plex/*" {
  capabilities = ["read"]
}
EOF

# Create k8s auth role
vault write auth/kubernetes/role/plex \
  bound_service_account_names=vault-auth \
  bound_service_account_namespaces=plex \
  policies=plex \
  ttl=1h
```

> **Note:** The claim token is only used on first boot to register the server.
> After that, Plex stores its auth in the config volume. If you ever need to
> re-claim (e.g. after deleting the config PVC), generate a fresh token and
> update the Vault secret.

## 3. Deploy via ArgoCD

Push to Forgejo. ArgoCD auto-syncs from `k8s/plex/` and `k8s/argocd/apps/plex.yaml`.

The Plex web UI will be available at `https://plex.example.com`.

## 4. Initial Plex Configuration

After first boot, open the web UI and complete the setup wizard:

1. **Name your server** (e.g. "my-plex")
2. **Add libraries:**
   - Movies → `/media/movies`
   - TV Shows → `/media/tv`
   - Music → `/media/music`
3. **Settings → Network:**
   - Secure connections: Preferred
   - Custom server access URLs: `https://plex.example.com`
4. **Settings → Library:**
   - Enable "Scan my library automatically" so new downloads from
     qBittorrent are picked up

## 5. Workflow: Torrent → Plex

Once both qBittorrent and Plex are running, the flow is:

1. Add a torrent via qBittorrent web UI, API, or watched folder
2. qBittorrent downloads to `/media/downloads/complete/`
3. Move or hardlink the finished file into `/media/media/movies/` (or tv/music)
4. Plex detects the new file and adds it to your library

For automated organization (moving downloads → media folders with proper
naming), consider adding Sonarr (TV) and Radarr (Movies) in the future.
These integrate directly with qBittorrent's API and handle the
download → rename → organize → notify Plex pipeline automatically.

## Media Directory Structure

```
/mnt/my-nfs/                    ← NFS share from nfs-01
├── downloads/                   ← qBittorrent writes here
│   ├── complete/
│   ├── incomplete/
│   └── watch/
└── media/                       ← Plex reads from here
    ├── movies/
    ├── tv/
    └── music/
```
