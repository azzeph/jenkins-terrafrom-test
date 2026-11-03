variable "libvirt_uri" {
  description = "Libvirt connection URI"
  type        = string
  default     = "qemu:///system"
}

variable "storage_pool_name" {
  description = "Name of the existing libvirt storage pool to store disks"
  type        = string
  default     = "default"
}

variable "network_name" {
  description = "Name of the libvirt network (must have DHCP enabled for automatic IP assignment)"
  type        = string
  default     = "default"
}

variable "base_image_name" {
  description = "Name of the base image volume in the libvirt pool"
  type        = string
  default     = "ubuntu-22.04-base.qcow2"
}

variable "base_image_url" {
  description = "Remote URL or local path to base cloud image"
  type        = string
  default     = "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
}

variable "admin_username" {
  description = "Default administrative user created via cloud-init"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key" {
  description = "SSH public key to inject into cloud-init authorized_keys"
  type        = string
  default     = ""
}

variable "default_memory" {
  description = "Default memory size in MiB if not specified in VM map"
  type        = number
  default     = 2048
}

variable "default_vcpu" {
  description = "Default vCPU count if not specified in VM map"
  type        = number
  default     = 2
}

variable "default_disk_capacity" {
  description = "Default disk capacity in bytes (10 GiB = 10737418240)"
  type        = number
  default     = 10737418240
}

variable "vms" {
  description = "Map of virtual machines with per-VM overrides"
  type = map(object({
    memory        = optional(number)
    vcpu          = optional(number)
    disk_capacity = optional(number)
  }))
  default = {
    "node-01" = {
      memory = 2048
      vcpu   = 2
    }
    "node-02" = {
      memory = 2048
      vcpu   = 2
    }
  }
}
