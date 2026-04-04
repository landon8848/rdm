resource "proxmox_virtual_environment_vm" "this" {
  name          = var.name
  description   = var.description
  node_name     = var.node_name
  vm_id         = var.vm_id
  tags          = sort(var.tags)
  on_boot       = true
  started       = true
  scsi_hardware = "virtio-scsi-single"

  clone {
    vm_id     = var.template_vm_id
    node_name = var.node_name
    full      = true
  }

  agent {
    enabled = var.agent_enabled
  }

  cpu {
    cores   = var.cores
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.datastore
    size         = var.disk_size_gb
    interface    = "scsi0"
    file_format  = "raw"
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  vga {
    type   = "serial0"
    memory = 16
  }

  initialization {
    user_data_file_id = var.user_data_file_id != "" ? var.user_data_file_id : null

    dns {
      domain  = var.dns_search_domain != "" ? var.dns_search_domain : null
      servers = var.dns_servers
    }
    ip_config {
      ipv4 {
        address = "${var.ip_address}/${var.cidr_prefix}"
        gateway = var.gateway
      }
    }
    user_account {
      username = "myadmin"
      keys     = [var.ssh_public_key]
    }
  }
}
