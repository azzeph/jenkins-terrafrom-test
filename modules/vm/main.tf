###############################################################################
# VM module
#
# Creates one virtual machine consisting of:
#   * a qcow2 overlay volume backed by the shared base image
#   * a cloud-init seed ISO (user-data / meta-data / network-config)
#   * the libvirt domain itself
#
# It waits for the guest to obtain an IP address and exposes hostname + IP.
###############################################################################

variable "name" {
  description = "Domain name / map key prefix"
  type        = string
}

variable "hostname" {
  description = "Guest hostname (also used as local-hostname in cloud-init)"
  type        = string
}

variable "pool" {
  description = "Storage pool name"
  type        = string
}

variable "base_volume_id" {
  description = "Volume ID of the base image (forces ordering)"
  type        = string
}

variable "backing_store_path" {
  description = "Filesystem path of the base image used as backing store"
  type        = string
}

variable "disk_capacity" {
  description = "Overlay disk capacity in bytes"
  type        = number
}

variable "vcpu" {
  description = "Number of vCPUs"
  type        = number
}

variable "memory_mib" {
  description = "Memory in MiB"
  type        = number
}

variable "network_name" {
  description = "libvirt network the VM connects to"
  type        = string
}

variable "network_cidr" {
  description = "CIDR of the network (used to compute the gateway/prefix)"
  type        = string
}

variable "static_ip" {
  description = "Static IPv4 address configured inside the guest"
  type        = string
}

variable "mac" {
  description = "MAC address for the primary interface (optional)"
  type        = string
  default     = null
}

variable "admin_user" {
  description = "Cloud-init admin user"
  type        = string
}

variable "iface_name" {
  description = "Primary NIC name inside the guest (predictable name, e.g. enp1s0)"
  type        = string
  default     = "enp1s0"
}

variable "domain" {
  description = "DNS search domain inside the guest"
  type        = string
  default     = "lab.local"
}

variable "ssh_public_key" {
  description = "SSH public key injected into the admin user"
  type        = string
}

variable "autostart" {
  description = "Start the VM on host boot"
  type        = bool
  default     = true
}

variable "firmware" {
  description = "Guest firmware: \"bios\" or \"uefi\". UEFI (OVMF) is the most reliable for q35 cloud images."
  type        = string
  default     = "uefi"

  validation {
    condition     = contains(["bios", "uefi"], var.firmware)
    error_message = "firmware must be either \"bios\" or \"uefi\""
  }
}

variable "ovmf_code_path" {
  description = "Path to the OVMF_CODE firmware (used when firmware = \"uefi\")"
  type        = string
  default     = "/usr/share/edk2/x64/OVMF_CODE.4m.fd"
}

variable "ovmf_vars_path" {
  description = "Path to the OVMF_VARS template (used when firmware = \"uefi\")"
  type        = string
  default     = "/usr/share/edk2/x64/OVMF_VARS.4m.fd"
}

locals {
  gateway = cidrhost(var.network_cidr, 1)
  prefix  = tonumber(split("/", var.network_cidr)[1])
}

###############################################################################
# Cloud-init
###############################################################################

locals {
  user_data = templatefile("${path.module}/templates/user-data.yaml.tftpl", {
    hostname       = var.hostname
    admin_user     = var.admin_user
    ssh_public_key = var.ssh_public_key
    domain         = var.domain
  })

  network_config = templatefile("${path.module}/templates/network-config.yaml.tftpl", {
    mac       = var.mac
    static_ip = var.static_ip
    prefix    = local.prefix
    gateway   = local.gateway
    iface     = var.iface_name
    domain    = var.domain
  })
}

resource "libvirt_cloudinit_disk" "seed" {
  name = "${var.name}-cloudinit"

  user_data = local.user_data

  meta_data = yamlencode({
    # Tie instance-id to the rendered cloud-init content so ANY change forces
    # cloud-init to re-run (otherwise a stale instance-id makes it skip).
    instance-id    = "${var.name}-${sha1(local.user_data)}"
    local-hostname = var.hostname
  })

  network_config = local.network_config
}

resource "libvirt_volume" "seed" {
  name = "${var.name}-cloudinit.iso"
  pool = var.pool

  # NOTE: the cloud-init disk is an ISO (cidata). Do not pin
  # target.format.type here — libvirt auto-detects it as "iso" and the
  # provider reads that back, which would otherwise cause an
  # "inconsistent result after apply" error.
  create = {
    content = {
      url = libvirt_cloudinit_disk.seed.path
    }
  }
}

###############################################################################
# Disks
###############################################################################

resource "libvirt_volume" "disk" {
  name     = "${var.name}.qcow2"
  pool     = var.pool
  capacity = var.disk_capacity

  target = {
    format = {
      type = "qcow2"
    }
  }

  backing_store = {
    path = var.backing_store_path
    format = {
      type = "qcow2"
    }
  }

  # Ensure the base image exists before creating the overlay.
  depends_on = [var.base_volume_id]
}

###############################################################################
# Domain
###############################################################################

resource "libvirt_domain" "this" {
  name        = var.name
  type        = "kvm"
  vcpu        = var.vcpu
  memory      = var.memory_mib
  memory_unit = "MiB"
  running     = true
  autostart   = var.autostart

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    # Explicit, unambiguous boot order: hard disk first, then cdrom.
    boot_devices = [{ dev = "hd" }, { dev = "cdrom" }]

    # UEFI (OVMF) is the recommended firmware for q35 cloud images. NVRAM is
    # per-VM so firmware variables don't clash between instances.
    firmware        = var.firmware == "uefi" ? "efi" : null
    loader          = var.firmware == "uefi" ? var.ovmf_code_path : null
    loader_type     = var.firmware == "uefi" ? "pflash" : null
    loader_readonly = var.firmware == "uefi" ? "yes" : null
    nv_ram = var.firmware == "uefi" ? {
      nv_ram   = "/var/lib/libvirt/qemu/nvram/${var.name}_VARS.fd"
      template = var.ovmf_vars_path
    } : null
  }

  # Use the host CPU so KVM acceleration actually applies. Without this a
  # guest can fall back to slow emulation and appear to "hang" early in boot.
  cpu = {
    mode = "host-passthrough"
  }

  # ACPI is required for UEFI; keep it on for BIOS too (q35 default).
  features = {
    acpi = true
  }

  devices = {
    disks = [
      {
        source = {
          # Use the explicit file path of the per-VM overlay so there is no
          # ambiguity about which volume gets attached. `source.file` beats
          # `source.volume` here: it binds vda to exactly node<N>.qcow2, whose
          # backing chain points at the shared base image.
          file = {
            file = libvirt_volume.disk.path
          }
        }
        target = {
          bus = "virtio"
          dev = "vda"
        }
        driver = {
          type = "qcow2"
        }
      },
      {
        device = "cdrom"
        source = {
          file = {
            file = libvirt_volume.seed.path
          }
        }
        target = {
          bus = "sata"
          dev = "sda"
        }
      }
    ]

    interfaces = [
      {
        type  = "network"
        model = { type = "virtio" }
        mac   = var.mac == null ? null : { address = var.mac }
        source = {
          network = {
            network = var.network_name
          }
        }
        # The guest is given a STATIC address (see network-config), so there
        # is nothing to wait for here — we already know the IP. Waiting on a
        # DHCP lease/guest-agent is unreliable for static configs. The IP is
        # verified separately via a host-side reachability gate.
      wait_for_ip = null }
    ]

    # Serial console + qemu-guest-agent channel for reliable IP discovery.
    consoles = [
      {
        target = {
          type = "serial"
          port = 0
        }
      }
    ]

    # Explicit serial port device (ISA serial on q35).
    serials = [
      {
        target = {
          port = 0
        }
      }
    ]

    channels = [
      {
        source = {
          qemu_vd_agent = {}
        }
        target = {
          virt_io = {
            name = "org.qemu.guest_agent.0"
          }
        }
      }
    ]

    graphics = [
      {
        vnc = {
          auto_port = true
          listen    = "127.0.0.1"
        }
      }
    ]
  }
}

###############################################################################
# Outputs
###############################################################################

output "name" {
  value = libvirt_domain.this.name
}

output "hostname" {
  value = var.hostname
}

output "mac" {
  value = try(libvirt_domain.this.devices.interfaces[0].mac.address, null)
}

output "ip" {
  value = var.static_ip
}

# The interface as reported by the provider.
output "interface" {
  value = try(libvirt_domain.this.devices.interfaces[0], null)
}
