terraform {
  required_version = ">= 1.5.0"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9.0"
    }
  }
}

provider "libvirt" {
  uri = var.libvirt_uri
}

# Download / provision base OS image once into the storage pool
resource "libvirt_volume" "base_image" {
  name = var.base_image_name
  pool = var.storage_pool_name

  target = {
    format = {
      type = "qcow2"
    }
  }

  create = {
    content = {
      url = var.base_image_url
    }
  }
}

# Deploy virtual machines using the modular configuration
module "vms" {
  source   = "./modules/libvirt_vm"
  for_each = var.vms

  name           = each.key
  memory         = lookup(each.value, "memory", var.default_memory)
  vcpu           = lookup(each.value, "vcpu", var.default_vcpu)
  disk_capacity  = lookup(each.value, "disk_capacity", var.default_disk_capacity)
  pool           = var.storage_pool_name
  network_name   = var.network_name
  base_volume_id = libvirt_volume.base_image.path
  ssh_public_key = var.ssh_public_key
  admin_username = var.admin_username
}
