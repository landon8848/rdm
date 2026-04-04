variable "name" {
  description = "VM name"
  type        = string
}

variable "vm_id" {
  description = "Proxmox VM ID"
  type        = number
}

variable "description" {
  description = "VM description"
  type        = string
  default     = ""
}

variable "tags" {
  description = "VM tags"
  type        = list(string)
  default     = []
}

variable "node_name" {
  description = "Proxmox node name"
  type        = string
}

variable "template_vm_id" {
  description = "VM ID of the cloud-init template to clone"
  type        = number
}

variable "cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "RAM in MB"
  type        = number
  default     = 2048
}

variable "disk_size_gb" {
  description = "Disk size in GB"
  type        = number
  default     = 20
}

variable "datastore" {
  description = "Proxmox storage pool ID"
  type        = string
  default     = "local-lvm"
}

variable "bridge" {
  description = "Network bridge"
  type        = string
  default     = "vmbr0"
}

variable "ip_address" {
  description = "Static IPv4 address (without prefix length)"
  type        = string
}

variable "cidr_prefix" {
  description = "CIDR prefix length"
  type        = number
  default     = 16
}

variable "gateway" {
  description = "Default gateway"
  type        = string
}

variable "dns_servers" {
  description = "DNS server IPs"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "ssh_public_key" {
  description = "SSH public key injected via cloud-init"
  type        = string
  sensitive   = true
}

variable "dns_search_domain" {
  description = "DNS search domain for cloud-init"
  type        = string
  default     = ""
}

variable "user_data_file_id" {
  description = "Proxmox file ID for cloud-init user_data snippet"
  type        = string
  default     = ""
}

variable "agent_enabled" {
  description = "Enable QEMU guest agent"
  type        = bool
  default     = true
}
