variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token (format: USER@REALM!TOKENID=SECRET)"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS certificate verification (needed for self-signed Proxmox certs)"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "prox"
}

variable "template_vm_id" {
  description = "VM ID of the Ubuntu 24.04 cloud-init template to clone"
  type        = number
  default     = 904
}

variable "datastore" {
  description = "Proxmox storage pool"
  type        = string
  default     = "local-lvm"
}

variable "bridge" {
  description = "Network bridge for VM NICs"
  type        = string
  default     = "vmbr0"
}

variable "gateway" {
  description = "Default gateway for VMs"
  type        = string
  default     = "192.168.1.1"
}

variable "cidr_prefix" {
  description = "CIDR prefix length for the LAN subnet"
  type        = number
  default     = 16
}

variable "ssh_public_key" {
  description = "SSH public key injected into VMs via cloud-init"
  type        = string
  sensitive   = true
}

variable "lxc_template_id" {
  description = "Proxmox CT template file ID for LXC containers (e.g. local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst)"
  type        = string
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}
