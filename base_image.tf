###############################################################################
# Base cloud image
#
# Downloaded once into the storage pool. Each VM uses it as a qcow2 backing
# store, so the base image is never modified and disks are thinly provisioned.
###############################################################################

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
}

