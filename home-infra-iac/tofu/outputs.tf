output "vm_ips" {
  description = "IP addresses of all provisioned VMs"
  value = {
    pihole_01 = module.pihole_01.ip_address
    vault     = module.vault.ip_address
    k0sm_00   = module.k0sm_00.ip_address
    k0sw_00   = module.k0sw_00.ip_address
    k0sw_01   = module.k0sw_01.ip_address
  }
}
