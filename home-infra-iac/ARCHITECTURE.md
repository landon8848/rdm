# rdm-local Architecture

```mermaid
graph TB
    subgraph internet["Internet"]
        CF["Cloudflare DNS\n(example.com)"]
        LE["Let's Encrypt ACME\n(DNS-01 challenge)"]
    end

    subgraph home["Home Network (192.168.1.0/16)"]
        Router["Netgear MR70\n192.168.1.1"]

        subgraph proxmox["Proxmox Host — prox (192.168.1.180)"]
            PiHole["Pi-hole VM\npihole-01 · 192.168.1.190\n\ndnsmasq wildcard:\n*.example.com → Traefik\nDirect: VMs bypass Traefik"]
            Vault["Vault VM\nvault · 192.168.1.191\n\nRaft storage\nKV secrets engine\nK8s auth method"]

            subgraph k8s["k0s Kubernetes Cluster"]
                subgraph cp["Control Plane — k0sm-00 (192.168.1.192)"]
                    CoreDNS["CoreDNS\nStub zone → Pi-hole\nfor example.com"]
                end

                subgraph workers["Workers — k0sw-00/01 (192.168.1.193-194)"]
                    subgraph network["Networking"]
                        MetalLB["MetalLB\nL2 pool: 192.168.1.200–230"]
                        Traefik["Traefik v3\n192.168.1.200\nHTTP→HTTPS redirect\nSSH TCP entrypoint :22"]
                        CertManager["cert-manager\nrdm-ca ClusterIssuer\nletsencrypt-prod ClusterIssuer"]
                    end

                    subgraph secrets["Secrets"]
                        VSO["Vault Secrets Operator\nSyncs Vault KV → K8s Secrets"]
                    end

                    subgraph gitops["GitOps"]
                        ArgoCD["ArgoCD\nargo.example.com\nApp of Apps pattern"]
                        Forgejo["Forgejo\ngit.example.com\nOrg: rdm"]
                    end
                end
            end
        end
    end

    subgraph mac["Developer Mac"]
        Repo["rdm-local repo\n(local clone)"]
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
    VSO -->|"K8s Secrets\n(cloudflare token,\nrepo creds, admin passwords)"| CertManager
    VSO -->|"K8s Secrets"| ArgoCD
    VSO -->|"K8s Secrets"| Forgejo

    %% GitOps flow
    Repo -->|"git push\n(SSH)"| Forgejo
    Forgejo -->|"watched by"| ArgoCD
    ArgoCD -->|"reconciles\nall namespaces"| k8s

    %% Ingress
    Traefik -->|"HTTPS routes"| ArgoCD
    Traefik -->|"HTTPS + SSH routes"| Forgejo
    MetalLB -->|"LoadBalancer IP\n192.168.1.200"| Traefik
```

## Services

| Service | URL | IP |
|---|---|---|
| Pi-hole | `http://pihole-01.example.com/admin` | 192.168.1.190 |
| Vault | `https://vault.example.com` | 192.168.1.191 |
| Traefik | `https://traefik.example.com` | 192.168.1.200 |
| ArgoCD | `https://argo.example.com` | 192.168.1.200 |
| Forgejo | `https://git.example.com` | 192.168.1.200 |

## Credential Storage

All secrets are stored in Vault at `secret/<service>/...` and synced into Kubernetes via VSO where needed. The Ansible pihole role reads Pi-hole's admin password from Vault at deploy time.
