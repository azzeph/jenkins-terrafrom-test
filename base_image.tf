###############################################################################
# Base cloud image
#
# Downloaded once into the storage pool. Each VM uses it as a qcow2 backing
# store, so the base image is never modified and disks are thinly provisioned.
###############################################################################

###############################################################################
# Storage pool
#
# The libvirt Terraform provider cannot create storage pools, only volumes
# inside an existing pool. This resource makes sure the pool named by
# `pool_name` exists before any volume is created.
#
# It is idempotent: if the pool already exists (e.g. the stock "default"
# pool) nothing happens. Otherwise a directory-backed pool is defined at
# <storage_pool_dir>/<pool_name> and started.
###############################################################################

resource "terraform_data" "storage_pool" {
  triggers_replace = {
    pool     = local.pool_name
    base_dir = var.storage_pool_dir
    uri      = var.libvirt_uri
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      pool='${local.pool_name}'
      uri='${var.libvirt_uri}'
      base_dir='${var.storage_pool_dir}'
      target="$${base_dir}/$${pool}"

      # Helper: run virsh, using sudo only when the default connection is used
      # and the socket is not accessible to the current user.
      virsh_cmd() { virsh -c "$${uri}" "$@"; }
      sudo_virsh() {
        if [ "$${uri}" = "qemu:///system" ] && ! virsh_cmd list >/dev/null 2>&1; then
          sudo virsh -c "$${uri}" "$@"
        else
          virsh_cmd "$@"
        fi
      }

      if sudo_virsh pool-info "$${pool}" >/dev/null 2>&1; then
        echo "Storage pool '$${pool}' already exists."
      else
        echo "Storage pool '$${pool}' not found - creating at $${target}"
        if [ "$${uri}" = "qemu:///system" ]; then
          sudo mkdir -p "$${target}"
          sudo chown libvirt-qemu:kvm "$${target}" 2>/dev/null || \
            sudo chown root:root "$${target}" 2>/dev/null || true
          sudo chmod 0711 "$${target}" 2>/dev/null || true
        else
          mkdir -p "$${target}"
        fi
        sudo_virsh pool-define-as "$${pool}" dir --target "$${target}"
        sudo_virsh pool-build "$${pool}"
      fi

      # Make sure the pool is active and persistent across host reboots.
      if ! sudo_virsh pool-info "$${pool}" | grep -qi 'State:.*running'; then
        sudo_virsh pool-start "$${pool}"
      fi
      sudo_virsh pool-autostart "$${pool}" || true
      sudo_virsh pool-info "$${pool}"
    EOT
  }
}

resource "libvirt_volume" "base" {
  name = var.base_image_name
  pool = local.pool_name

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

  depends_on = [terraform_data.storage_pool]
}
