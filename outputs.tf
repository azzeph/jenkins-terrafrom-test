output "vm_list" {
  description = "List of created virtual machines with hostnames and primary IP addresses"
  value = [
    for k, vm in module.vms : {
      hostname     = vm.name
      primary_ip   = vm.primary_ip
      ip_addresses = vm.ip_addresses
    }
  ]
}

output "vm_map" {
  description = "Map of virtual machines keyed by hostname with their IP address"
  value = {
    for k, vm in module.vms : vm.name => vm.primary_ip
  }
}
