###############################################################################
# Project
###############################################################################

variable "project_name" {
  description = "Logical project name. Used to derive network name, pool name and per-VM hostnames (unless overridden)."
  type        = string
  default     = "lab"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,30}$", var.project_name))
    error_message = "project_name must be lowercase alphanumeric with dashes, up to 31 chars."
  }
}

###############################################################################
# Root variables
###############################################################################

variable "libvirt_uri" {
  description = "libvirt connection URI (e.g. qemu:///system for the system daemon, qemu:///session for a user session)"
  type        = string
  default     = "qemu:///system"
}

variable "pool_name" {
  description = "The libvirt storage pool used for images and cloud-init ISOs. Defaults to the stock 'default' pool; set to e.g. '<project>-pool' for a dedicated pool (created automatically)."
  type        = string
  default     = "default"
}

variable "storage_pool_dir" {
  description = "Parent directory where a dedicated (dir-type) storage pool is created when pool_name does not exist yet."
  type        = string
  default     = "/var/lib/libvirt/images"
}

variable "base_image_url" {
  description = "URL of the cloud image used as the backing store for every VM"
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "base_image_name" {
  description = "Name of the base volume inside the storage pool"
  type        = string
  default     = "ubuntu-noble-base.qcow2"
}

variable "vm_count" {
  description = "How many VMs to create when `vms` is not set explicitly. Hostnames are '<vm_name_prefix><index>' (1-based)."
  type        = number
  default     = 2

  validation {
    condition     = var.vm_count >= 2
    error_message = "At least two VMs must be defined (vm_count >= 2)."
  }
}

variable "vm_name_prefix" {
  description = "Prefix used for auto-generated VM names/hostnames (e.g. 'node' -> node1, node2). Empty string derives '<project_name>-node'."
  type        = string
  default     = ""
}

variable "vm_ip_start_offset" {
  description = "Offset inside the network CIDR where the first auto-generated VM address begins (default 11 -> x.x.x.11)."
  type        = number
  default     = 11
}

variable "vm_default_vcpu" {
  description = "Default vCPU count for auto-generated VMs"
  type        = number
  default     = 2
}

variable "vm_default_memory_mib" {
  description = "Default memory (MiB) for auto-generated VMs"
  type        = number
  default     = 2048
}

variable "vm_disk_size" {
  description = "Disk capacity of each VM in bytes (used as the overlay volume capacity)"
  type        = number
  default     = 21474836480 # 20 GiB
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

variable "network_name" {
  description = "Name of the libvirt network to create. Empty string derives '<project_name>-net'."
  type        = string
  default     = ""
}

variable "network_cidr" {
  description = "IPv4 CIDR of the virtual network"
  type        = string
  default     = "10.10.0.0/24"
}

variable "network_gateway" {
  description = "Gateway / host address of the virtual network"
  type        = string
  default     = "10.10.0.1"
}

variable "network_domain" {
  description = "DNS domain for the virtual network. Empty string derives '<project_name>.local'."
  type        = string
  default     = ""
}

variable "network_isolation" {
  description = "If true, the network is isolated (no NAT forwarding to the host network). If false, NAT is used."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# SSH
# ---------------------------------------------------------------------------

variable "admin_user" {
  description = "Default cloud-init user created on the VMs"
  type        = string
  default     = "ubuntu"
}

variable "iface_name" {
  description = "Primary NIC name inside the guest (predictable name, e.g. enp1s0)"
  type        = string
  default     = "enp1s0"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key injected into every VM (expanduser supported)"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

# ---------------------------------------------------------------------------
# Firmware
# ---------------------------------------------------------------------------

variable "firmware" {
  description = "Guest firmware: 'bios' or 'uefi'. UEFI (OVMF) is recommended for q35 cloud images."
  type        = string
  default     = "uefi"

  validation {
    condition     = contains(["bios", "uefi"], var.firmware)
    error_message = "firmware must be either 'bios' or 'uefi'"
  }
}

variable "ovmf_code_path" {
  description = "Path to OVMF_CODE firmware (used when firmware = 'uefi')"
  type        = string
  default     = "/usr/share/edk2/x64/OVMF_CODE.4m.fd"
}

variable "ovmf_vars_path" {
  description = "Path to OVMF_VARS template (used when firmware = 'uefi')"
  type        = string
  default     = "/usr/share/edk2/x64/OVMF_VARS.4m.fd"
}

# ---------------------------------------------------------------------------
# VM definitions
# ---------------------------------------------------------------------------

variable "vms" {
  description = "Optional explicit map of virtual machines. When null (default) VMs are auto-generated from project_name + vm_count + vm_name_prefix."
  type = map(object({
    hostname   = string
    vcpu       = optional(number, 2)
    memory_mib = optional(number, 2048)
    ip         = string
    mac        = optional(string)
    autostart  = optional(bool, true)
  }))
  default = null
}
