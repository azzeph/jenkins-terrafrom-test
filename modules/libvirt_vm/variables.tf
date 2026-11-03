variable "name" {
  description = "Hostname and base name for VM resources"
  type        = string
}

variable "memory" {
  description = "RAM allocated to the VM in MiB"
  type        = number
  default     = 2048
}

variable "vcpu" {
  description = "Number of vCPUs"
  type        = number
  default     = 2
}

variable "pool" {
  description = "Libvirt storage pool name"
  type        = string
  default     = "default"
}

variable "network_name" {
  description = "Libvirt virtual network name"
  type        = string
  default     = "default"
}

variable "disk_capacity" {
  description = "Disk capacity in bytes (e.g. 10GB = 10737418240)"
  type        = number
  default     = 10737418240 # 10 GiB
}

variable "base_volume_id" {
  description = "Path/ID of the backing base volume image for CoW"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for cloud-init authentication"
  type        = string
  default     = ""
}

variable "admin_username" {
  description = "Default admin user created by cloud-init"
  type        = string
  default     = "ubuntu"
}
