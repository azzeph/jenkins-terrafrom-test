###############################################################################
# Root composition: network + N virtual machines
###############################################################################

locals {
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))

  # --- Derived names (project_name is the single source of truth) -----------
  network_name   = var.network_name != "" ? var.network_name : "${var.project_name}-net"
  pool_name      = var.pool_name
  network_domain = var.network_domain != "" ? var.network_domain : "${var.project_name}.local"
  vm_name_prefix = var.vm_name_prefix != "" ? var.vm_name_prefix : "${var.project_name}-node"

  # --- VM map: explicit override wins, otherwise auto-generate -------------
  vms = var.vms != null ? var.vms : {
    for i in range(1, var.vm_count + 1) :
    "${local.vm_name_prefix}${i}" => {
      hostname   = "${local.vm_name_prefix}${i}"
      vcpu       = var.vm_default_vcpu
      memory_mib = var.vm_default_memory_mib
      ip         = cidrhost(var.network_cidr, var.vm_ip_start_offset + i - 1)
      mac        = null
      autostart  = true
    }
  }

  # Deterministic, locally-administered MAC addresses derived from the VM key.
  # Format: 52:54:00:xx:xx:xx (the QEMU/KVM OUI range).
  vm_macs = {
    for idx, key in sort(keys(local.vms)) :
    key => "52:54:00:${substr(sha256(key), 0, 2)}:${substr(sha256(key), 2, 2)}:${substr(sha256(key), 4, 2)}"
  }
}

# ---------------------------------------------------------------------------
# Network (module)
# ---------------------------------------------------------------------------
module "network" {
  source = "./modules/network"

  name     = local.network_name
  cidr     = var.network_cidr
  gateway  = var.network_gateway
  domain   = local.network_domain
  isolated = var.network_isolation

  # Reserve the static addresses for each VM in DHCP as well, so that
  # `virsh net-dhcp-leases` (and the `lease` IP-discovery source) resolve them.
  dhcp_hosts = [
    for key, vm in local.vms : {
      name = vm.hostname
      mac  = local.vm_macs[key]
      ip   = vm.ip
    }
  ]
}

# ---------------------------------------------------------------------------
# Virtual machines (module, for_each over the map)
# ---------------------------------------------------------------------------
module "vm" {
  source   = "./modules/vm"
  for_each = local.vms

  name       = each.key
  hostname   = each.value.hostname
  pool       = local.pool_name
  vcpu       = each.value.vcpu
  memory_mib = each.value.memory_mib
  autostart  = each.value.autostart
  mac        = each.value.mac != null ? each.value.mac : local.vm_macs[each.key]

  # Firmware
  firmware       = var.firmware
  ovmf_code_path = var.ovmf_code_path
  ovmf_vars_path = var.ovmf_vars_path

  # Base image / overlay disk
  base_volume_id     = libvirt_volume.base.id
  backing_store_path = libvirt_volume.base.path
  disk_capacity      = var.vm_disk_size

  # Networking
  network_name = module.network.name
  network_cidr = var.network_cidr
  static_ip    = each.value.ip

  # Cloud-init
  admin_user     = var.admin_user
  ssh_public_key = local.ssh_public_key
  iface_name     = var.iface_name
  domain         = local.network_domain

  depends_on = [module.network]
}
