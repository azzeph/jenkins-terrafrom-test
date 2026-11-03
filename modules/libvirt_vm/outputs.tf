output "id" {
  description = "Domain ID"
  value       = libvirt_domain.vm.id
}

output "name" {
  description = "Hostname/Domain name"
  value       = libvirt_domain.vm.name
}

output "ip_addresses" {
  description = "All resolved IP addresses for the virtual machine"
  value = flatten([
    for iface in data.libvirt_domain_interface_addresses.vm_ip.interfaces : [
      for addr in iface.addrs : addr.addr
    ]
  ])
}

output "primary_ip" {
  description = "Primary IP address (first found, typically IPv4)"
  value = try(
    [
      for iface in data.libvirt_domain_interface_addresses.vm_ip.interfaces : [
        for addr in iface.addrs : addr.addr if addr.type == "ipv4"
      ]
    ][0][0],
    ""
  )
}
