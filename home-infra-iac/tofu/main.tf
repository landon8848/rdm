provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure
}

locals {
  common = {
    node_name      = var.proxmox_node
    template_vm_id = var.template_vm_id
    datastore      = var.datastore
    bridge         = var.bridge
    gateway        = var.gateway
    cidr_prefix    = var.cidr_prefix
    ssh_public_key = var.ssh_public_key
    # Once pihole-01 is up, it becomes primary DNS for the rest
    # Fallback: OpenDNS (DNSSEC-validating)
    dns_servers = ["192.168.1.6", "208.67.222.222"]
    # k0s nodes must NOT have example.com as a DNS search domain —
    # kubelet propagates it into pod resolv.conf, breaking external DNS resolution
    # via ndots:5 (external names get .example.com appended first,
    # hitting the PiHole wildcard instead of the real IP).
    dns_search_domain = ""
  }
}

module "pihole_01" {
  source = "./modules/proxmox_vm"

  name         = "pihole-01"
  vm_id        = 206
  description  = "PiHole DNS server"
  tags         = ["infra", "dns"]
  ip_address   = "192.168.1.6"
  cores        = 1
  memory_mb    = 1024
  disk_size_gb = 8

  # Bootstrap with OpenDNS upstream; pihole isn't up yet during provisioning
  dns_servers       = ["208.67.222.222", "208.67.220.220"]
  dns_search_domain = "example.com"
  node_name         = local.common.node_name
  template_vm_id = local.common.template_vm_id
  datastore      = local.common.datastore
  bridge         = local.common.bridge
  gateway        = local.common.gateway
  cidr_prefix    = local.common.cidr_prefix
  ssh_public_key = local.common.ssh_public_key
}

module "vault" {
  source = "./modules/proxmox_vm"

  name         = "vault"
  vm_id        = 205
  description  = "HashiCorp Vault secrets backend"
  tags         = ["infra", "secrets"]
  ip_address   = "192.168.1.140"
  cores        = 2
  memory_mb    = 2048
  disk_size_gb = 20

  dns_servers       = local.common.dns_servers
  dns_search_domain = local.common.dns_search_domain
  node_name         = local.common.node_name
  template_vm_id    = local.common.template_vm_id
  datastore         = local.common.datastore
  bridge            = local.common.bridge
  gateway           = local.common.gateway
  cidr_prefix       = local.common.cidr_prefix
  ssh_public_key    = local.common.ssh_public_key
}

module "k0sm_00" {
  source = "./modules/proxmox_vm"

  name         = "k0sm-00"
  vm_id        = 202
  description  = "k0s Kubernetes control plane"
  tags         = ["k8s", "control-plane"]
  ip_address   = "192.168.1.247"
  cores        = 2
  memory_mb    = 4096
  disk_size_gb = 32

  dns_servers       = local.common.dns_servers
  dns_search_domain = local.common.dns_search_domain
  node_name         = local.common.node_name
  template_vm_id    = local.common.template_vm_id
  datastore         = local.common.datastore
  bridge            = local.common.bridge
  gateway           = local.common.gateway
  cidr_prefix       = local.common.cidr_prefix
  ssh_public_key    = local.common.ssh_public_key
}

module "k0sw_00" {
  source = "./modules/proxmox_vm"

  name         = "k0sw-00"
  vm_id        = 203
  description  = "k0s Kubernetes worker node 0"
  tags         = ["k8s", "worker"]
  ip_address   = "192.168.1.143"
  cores        = 4
  memory_mb    = 8192
  disk_size_gb = 64

  dns_servers       = local.common.dns_servers
  dns_search_domain = local.common.dns_search_domain
  node_name         = local.common.node_name
  template_vm_id    = local.common.template_vm_id
  datastore         = local.common.datastore
  bridge            = local.common.bridge
  gateway           = local.common.gateway
  cidr_prefix       = local.common.cidr_prefix
  ssh_public_key    = local.common.ssh_public_key
}

module "nfs_01" {
  source = "./modules/proxmox_lxc"

  name             = "nfs-01"
  vm_id            = 207
  description      = "NFS server — media storage (USB-backed)"
  tags             = ["infra", "storage"]
  ip_address       = "192.168.1.125"
  cores            = 1
  memory_mb        = 512
  disk_size_gb     = 4
  template_file_id = var.lxc_template_id

  # Bind-mount the USB drive from the Proxmox host into the container.
  # Prerequisites:
  #   1. USB drive formatted and mounted at /mnt/media-usb on the Proxmox host
  #   2. Entry in /etc/fstab on the host for persistence
  mount_points = [
    {
      host_path      = "/mnt/media-usb"
      container_path = "/mnt/media-usb"
    }
  ]

  dns_servers       = local.common.dns_servers
  dns_search_domain = "example.com"
  node_name         = local.common.node_name
  datastore         = local.common.datastore
  bridge            = local.common.bridge
  gateway           = local.common.gateway
  cidr_prefix       = local.common.cidr_prefix
  ssh_public_key    = local.common.ssh_public_key
}

module "k0sw_01" {
  source = "./modules/proxmox_vm"

  name         = "k0sw-01"
  vm_id        = 204
  description  = "k0s Kubernetes worker node 1"
  tags         = ["k8s", "worker"]
  ip_address   = "192.168.1.135"
  cores        = 4
  memory_mb    = 6144
  disk_size_gb = 64

  dns_servers       = local.common.dns_servers
  dns_search_domain = local.common.dns_search_domain
  node_name         = local.common.node_name
  template_vm_id    = local.common.template_vm_id
  datastore         = local.common.datastore
  bridge            = local.common.bridge
  gateway           = local.common.gateway
  cidr_prefix       = local.common.cidr_prefix
  ssh_public_key    = local.common.ssh_public_key
}
