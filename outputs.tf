###############################################################################
# Outputs: hostname and IP address for every created VM
#
# Each guest is configured with a STATIC address via cloud-init, so the IP is
# known at plan time. We still cross-check with the provider's interface data
# (DHCP lease / qemu-guest-agent) when available and fall back to the
# configured address otherwise.
###############################################################################

data "libvirt_domain_interface_addresses" "this" {
  for_each = module.vm

  domain = each.value.name
  source = "any"

  depends_on = [module.vm]
}

locals {
  vm_addresses = {
    for key, vm in module.vm : key => coalesce(
      # 1. address reported by the provider (lease / guest-agent), if any
      try(
        [for i in data.libvirt_domain_interface_addresses.this[key].interfaces :
          [for a in i.addrs : a.addr if a.type == "ipv4" && !startswith(a.addr, "127.")][0]
        ][0],
        null
      ),
      # 2. the statically configured address (authoritative here)
      vm.ip,
      local.vms[key].ip
    )
  }
}

output "vms" {
  description = "Map of VM name -> { hostname, ip, mac }"
  value = {
    for key, vm in module.vm : key => {
      hostname = vm.hostname
      ip       = local.vm_addresses[key]
      mac      = vm.mac
    }
  }
}

output "hostnames" {
  description = "Map of VM name -> guest hostname"
  value       = { for key, vm in module.vm : key => vm.hostname }
}

output "ips" {
  description = "Map of VM name -> IP address"
  value       = local.vm_addresses
}

output "ssh_commands" {
  description = "Ready-to-use SSH commands"
  value = {
    for key, vm in module.vm :
    key => "ssh ${var.admin_user}@${local.vm_addresses[key]}"
  }
}

output "project_name" {
  description = "Logical project name used to derive resource names"
  value       = var.project_name
}

output "network_name" {
  description = "Name of the created libvirt network"
  value       = module.network.name
}

output "pool_name" {
  description = "Storage pool used for images and cloud-init ISOs"
  value       = local.pool_name
}
