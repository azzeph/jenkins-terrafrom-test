# Cloud-init configuration: user-data, meta-data, network-config
resource "libvirt_cloudinit_disk" "commoninit" {
  name = "${var.name}-cloudinit"

  meta_data = <<-EOF
    instance-id: ${var.name}
    local-hostname: ${var.name}
  EOF

  user_data = <<-EOF
    #cloud-config
    hostname: ${var.name}
    fqdn: ${var.name}.local
    users:
      - name: ${var.admin_username}
        sudo: ALL=(ALL) NOPASSWD:ALL
        groups: sudo
        shell: /bin/bash
        lock_passwd: false
        ${length(var.ssh_public_key) > 0 ? "ssh_authorized_keys:\n          - ${var.ssh_public_key}" : ""}
    package_update: false
    package_upgrade: false
    packages:
      - qemu-guest-agent
    runcmd:
      - systemctl enable --now qemu-guest-agent
  EOF

    network_config = <<-EOF
      version: 2
      ethernets:
      enp1s0:
        dhcp4: true
  EOF
}

# Cloud-init disk uploaded as a volume into the storage pool
resource "libvirt_volume" "cloudinit_volume" {
  name = "${var.name}-cloudinit.iso"
  pool = var.pool

  create = {
    content = {
      url = libvirt_cloudinit_disk.commoninit.path
    }
  }
}

# CoW root volume backed by the base OS image
resource "libvirt_volume" "disk" {
  name     = "${var.name}-root.qcow2"
  pool     = var.pool
  capacity = var.disk_capacity

  target = {
    format = {
      type = "qcow2"
    }
  }

  backing_store = {
    path = var.base_volume_id
    format = {
      type = "qcow2"
    }
  }
}

# Virtual machine domain
resource "libvirt_domain" "vm" {
  name        = var.name
  type        = "kvm"
  memory      = var.memory
  memory_unit = "MiB"
  vcpu        = var.vcpu

  cpu = {
    mode = "host-passthrough"
  }

  features = {
    acpi = true
    apic = {}
  }

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    boot_devices = [
      {
        dev = "hd"
      }
    ]
  }

  devices = {
    disks = [
      {
        source = {
          volume = {
            pool   = libvirt_volume.disk.pool
            volume = libvirt_volume.disk.name
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
        driver = {
          type = "qcow2"
        }
      },
      {
        device = "cdrom"
        source = {
          volume = {
            pool   = libvirt_volume.cloudinit_volume.pool
            volume = libvirt_volume.cloudinit_volume.name
          }
        }
        target = {
          dev = "sda"
          bus = "sata"
        }
      }
    ]

    interfaces = [
      {
        type  = "network"
        model = { type = "virtio" }
        source = {
          network = {
            network = var.network_name
          }
        }
        wait_for_ip = {
          source  = "any"
          timeout = 300
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

    consoles = [
      {
        target = {
          port = 0
          type = "serial"
        }
      }
    ]

    channels = [
      {
        target = {
          virt_io = {
            name = "org.qemu.guest_agent.0"
          }
        }
      }
    ]
  }

  running = true
}

# Data source to extract IP addresses from DHCP leases or QEMU Guest Agent
data "libvirt_domain_interface_addresses" "vm_ip" {
  domain = libvirt_domain.vm.id
  source = "any"

  depends_on = [libvirt_domain.vm]
}
