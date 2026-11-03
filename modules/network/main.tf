###############################################################################
# Network module - isolated/NAT libvirt network with DHCP reservations
###############################################################################

variable "name" {
  description = "Network name"
  type        = string
}

variable "cidr" {
  description = "IPv4 CIDR"
  type        = string
}

variable "gateway" {
  description = "Gateway address (host side)"
  type        = string
}

variable "domain" {
  description = "DNS domain"
  type        = string
  default     = "lab.local"
}

variable "isolated" {
  description = "When true, no forwarding to the host network (isolated network)"
  type        = bool
  default     = false
}

variable "autostart" {
  description = "Start the network automatically on host boot"
  type        = bool
  default     = true
}

variable "dhcp_hosts" {
  description = "Static DHCP reservations: list of { name, mac, ip }"
  type = list(object({
    name = string
    mac  = string
    ip   = string
  }))
  default = []
}

# NAT forward (default) or fully isolated network.
resource "libvirt_network" "this" {
  name      = var.name
  autostart = var.autostart

  forward = var.isolated ? null : {
    mode = "nat"
  }

  # `bridge` is required for isolated networks that use DHCP/DNS on the host.
  bridge = var.isolated ? {
    name = "virbr-${substr(sha1(var.name), 0, 6)}"
  } : null

  domain = {
    name = var.domain
    # local_only must be false so dnsmasq FORWARDS external queries to the
    # host's resolvers. With local_only=yes the guest can resolve local names
    # but external DNS (and therefore apt) times out.
    local_only = "no"
  }

  dns = {
    enable = "yes"
  }

  ips = [
    {
      family  = "ipv4"
      address = var.gateway
      prefix  = tonumber(split("/", var.cidr)[1])
      dhcp = {
        ranges = [
          {
            # The range must CONTAIN every static reservation, otherwise
            # dnsmasq ignores the host entries and never records a lease for
            # them (which breaks `wait_for_ip` / `net-dhcp-leases`).
            # Reserve .1 for the gateway and start reservations from .10.
            start = cidrhost(var.cidr, 10)
            end   = cidrhost(var.cidr, 254)
          }
        ]
        hosts = [
          for h in var.dhcp_hosts : {
            name = h.name
            mac  = h.mac
            ip   = h.ip
          }
        ]
      }
    }
  ]
}

output "id" {
  value = libvirt_network.this.id
}

output "name" {
  value = libvirt_network.this.name
}
