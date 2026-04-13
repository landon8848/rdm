# my-local Architecture

```mermaid
graph TB
    subgraph internet["Internet"]
        CF["dns-provider DNS\n(example.com)"]
        LE["Let's Encrypt ACME\n(DNS-01 challenge)"]
    end

    subgraph home["Home Network (192.168.1.0/16)"]
        Router["router-ap\n192.168.1.1"]

        subgraph proxmox["Proxmox Host — prox (192.168.1.148)"]
            PiHole["Pi-hole VM\npihole-01 · 192.168.1.6\n\ndnsmasq wildcard:\n*.example.com → Traefik\nDirect: VMs bypass Traefik"]
            Vault["Vault VM\nvault · 192.168.1.140\n\nRaft storage\nKV secrets engine\nK8s auth method"]
            NFS["NFS LXC\nnfs-01 · 192.168.1.125\n\nUSB-backed media storage\nNFS export: /mnt/media-usb"]

            subgraph k8s["k0s Kubernetes Cluster"]
                subgraph cp["Control Plane — k0sm-00 (192.168.1.247)"]
                    CoreDNS["CoreDNS\nStub zone → Pi-hole\nfor example.com"]
                end

                subgraph workers["Workers — k0sw-00/01 (192.168.1.143-194)"]
                    subgraph network["Networking"]
                        MetalLB["MetalLB\nL2 pool: 192.168.1.87–230"]
                        Traefik["Traefik v3\n192.168.1.87\nHTTP→HTTPS redirect\nSSH TCP entrypoint :22"]
                        CertManager["cert-manager\nrdm-ca ClusterIssuer\nletsencrypt-prod ClusterIssuer"]
                    end

                    subgraph secrets["Secrets"]
                        VSO["Vault Secrets Operator\nSyncs Vault KV → K8s Secrets"]
                    end

                    subgraph data["Data"]
                        CNPG["CloudNativePG Operator\nManages PostgreSQL clusters\nper-namespace via Cluster CRDs"]
                    end

                    subgraph identity["Identity & SSO"]
                        Authentik["Authentik\nauth.example.com\nOIDC/SAML/ForwardAuth\nProxy outpost for Traefik"]
                    end

                    subgraph gitops["GitOps"]
                        ArgoCD["ArgoCD\nargo.example.com\nApp of Apps pattern\nOIDC via Authentik"]
                        Forgejo["Forgejo\ngit.example.com\nOrg: my"]
                    end

                    subgraph media["Media"]
                        qBittorrent["qBittorrent + Gluetun\nqbit.example.com\nMullvad WireGuard VPN\nNFS media from nfs-01"]
                        Plex["Plex Media Server\nplex.example.com\nDirect play (no transcoding)\nNFS media from nfs-01"]
                    end
                end
            end
        end
    end

    subgraph mac["Developer Mac"]
        Repo["my-local repo\n(local clone)"]
    end

    %% DNS resolution
    Router -->|"DHCP clients\nuse router DNS"| PiHole
    CoreDNS -->|"stub zone\nexample.com"| PiHole
    PiHole -->|"upstream DNS"| CF

    %% TLS / ACME
    CertManager -->|"DNS-01 challenge"| CF
    CF <-->|"ACME API"| LE
    CertManager -->|"wildcard cert\n*.example.com"| Vault

    %% Secrets flow
    Vault -->|"KV secrets\nvia K8s auth"| VSO
    VSO -->|"K8s Secrets\n(dns-provider token,\nrepo creds, admin passwords)"| CertManager
    VSO -->|"K8s Secrets"| ArgoCD
    VSO -->|"K8s Secrets"| Forgejo
    VSO -->|"K8s Secrets\n(secret key, DB creds)"| Authentik

    %% GitOps flow
    Repo -->|"git push\n(SSH)"| Forgejo
    Forgejo -->|"watched by"| ArgoCD
    ArgoCD -->|"reconciles\nall namespaces"| k8s

    %% Data
    CNPG -->|"manages\nPostgreSQL cluster"| Authentik

    %% Identity
    Authentik -->|"OIDC provider"| ArgoCD
    Traefik -->|"ForwardAuth\n(proxy outpost)"| Authentik

    %% Ingress
    Traefik -->|"HTTPS routes"| ArgoCD
    Traefik -->|"HTTPS + SSH routes"| Forgejo
    Traefik -->|"HTTPS route"| qBittorrent
    Traefik -->|"HTTPS route"| Plex
    Traefik -->|"HTTPS route"| Authentik
    MetalLB -->|"LoadBalancer IP\n192.168.1.87"| Traefik

    Authentik -->|"OIDC realm"| proxmox

    qBittorrent -->|"all torrent traffic\nvia WireGuard"| internet
    qBittorrent -->|"NFS mount\ndownloads (rw)"| NFS
    Plex -->|"NFS mount\nmedia (ro)"| NFS
```

## Services

| Service | URL | IP |
|---|---|---|
| Pi-hole | `http://pihole-01.example.com/admin` | 192.168.1.6 |
| Vault | `https://vault.example.com` | 192.168.1.140 |
| NFS | — (NFS export, no web UI) | 192.168.1.125 |
| Traefik | `https://traefik.example.com` | 192.168.1.87 |
| ArgoCD | `https://argo.example.com` | 192.168.1.87 |
| Forgejo | `https://git.example.com` | 192.168.1.87 |
| qBittorrent | `https://qbit.example.com` | 192.168.1.87 |
| Authentik | `https://auth.example.com` | 192.168.1.87 |
| Plex | `https://plex.example.com` | 192.168.1.87 |

## Credential Storage

All secrets are stored in Vault at `secret/<service>/...` and synced into Kubernetes via VSO where needed. The Ansible pihole role reads Pi-hole's admin password from Vault at deploy time.
