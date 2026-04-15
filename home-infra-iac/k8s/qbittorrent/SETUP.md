# qBittorrent Setup — Prerequisites

qBittorrent mounts the `downloads/` subtree of the NFS share on `nfs-01`
(192.168.1.125). Plex mounts the `media/` subtree separately.

## 1. USB Drive on the Proxmox Host

The USB drive is plugged into `prox` and bind-mounted into the `nfs-01` LXC.
If the drive isn't already formatted and mounted:

```bash
ssh myadmin@192.168.1.148

# Identify the USB device
lsblk
blkid /dev/sda1   # note the UUID

# Format as xfs (destructive — only if the drive is empty/new)
sudo mkfs.xfs -f -L my-nfs /dev/sda1

# Mount it at /mnt/my-nfs
sudo mkdir -p /mnt/my-nfs
echo "UUID=<your-uuid>  /mnt/my-nfs  xfs  defaults,nofail,x-systemd.device-timeout=30  0  2" \
  | sudo tee -a /etc/fstab
sudo mount -a
```

## 2. Provision the NFS LXC

`nfs-01` is managed entirely by Ansible — the LXC is created via `pct` and
then configured in place. See `ansible/playbooks/nfs.yml` for details.

> **Why not OpenTofu?** The bpg/proxmox provider can't create privileged LXCs
> with bind mounts using an API token — Proxmox hardcodes those operations to
> `root@pam`. Ansible talks to `prox` over SSH and sidesteps that restriction.

```bash
cd ansible/
ansible-playbook -i inventory/hosts.yml playbooks/nfs.yml
```

This will:

- Create the `nfs-01` LXC (ID 207, 192.168.1.125) with `/mnt/my-nfs` bind-mounted
  from the host
- Bootstrap `myadmin` + passwordless sudo inside the container
- Install `nfs-kernel-server`, create the directory layout, and configure exports

Exports configured by the role:

| Export | Clients | Notes |
|---|---|---|
| `/mnt/my-nfs/downloads` | `192.168.1.0/16` | qBittorrent writes here |
| `/mnt/my-nfs/media` | `192.168.1.0/16` | Plex reads from here |
| `/mnt/my-nfs/dropbox` | `192.168.1.148` | Prox host only for now |

Verify from a k8s worker:

```bash
ssh myadmin@192.168.1.143
showmount -e 192.168.1.125
```

K8s workers also need `nfs-common` installed to mount NFS volumes — this is
handled by the common role via `base_packages` in `group_vars/all.yml`.

## 3. Vault Secrets for vpn-provider VPN

```bash
# Get your WireGuard private key from https://vpn-provider.net/en/account/wireguard-config
vault kv put secret/qbittorrent/vpn \
  WIREGUARD_PRIVATE_KEY="<your-vpn-provider-wireguard-private-key>" \
  WIREGUARD_ADDRESSES="<your-vpn-provider-ipv4-address>/32"
```

Vault policy + k8s auth role:

```bash
vault policy write qbittorrent - <<EOF
path "secret/data/qbittorrent/*" {
  capabilities = ["read"]
}
EOF

vault write auth/kubernetes/role/qbittorrent \
  bound_service_account_names=vault-auth \
  bound_service_account_namespaces=qbittorrent \
  policies=qbittorrent \
  ttl=1h
```

## 4. Deploy via ArgoCD

Push to Forgejo. ArgoCD auto-syncs `k8s/qbittorrent/` and
`k8s/argocd/apps/qbittorrent.yaml`.

The web UI is at `https://qbit.example.com`. Grab the initial
temporary password from the container logs:

```bash
kubectl logs -n qbittorrent deploy/qbittorrent -c qbittorrent | grep "temporary password"
```

## 5. Configure Watched Folder

In the qBittorrent web UI → **Tools → Options → Downloads**:

- Default save path: `/downloads/complete`
- Keep incomplete torrents in: `/downloads/incomplete`
- Automatically add torrents from: `/downloads/watch`

Dropping any `.torrent` into `downloads/watch/` on the NFS share will pick it
up automatically.

## 6. Home Assistant Integration

qBittorrent has a native HA integration. In Home Assistant → **Settings →
Devices & Services → Add Integration → qBittorrent**:

- Host: `qbit.example.com`
- Port: `443`
- SSL: `true`
- Username/Password: your qBittorrent web UI credentials

## Directory Structure

```
/mnt/my-nfs/              ← USB drive (xfs, bind-mounted from prox into nfs-01)
├── downloads/             ← qBittorrent (NFS export, 192.168.1.0/16)
│   ├── complete/
│   ├── incomplete/
│   └── watch/
├── media/                 ← Plex (NFS export, 192.168.1.0/16)
│   ├── movies/
│   ├── tv/
│   └── music/
└── dropbox/               ← prox host only (NFS export, 192.168.1.148)
```
