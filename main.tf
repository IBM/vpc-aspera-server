##############################################################################
# Terraform Main IaC
##############################################################################

data "ibm_is_volumes" "existing" {
  volume_name = var.export_volume_name
}

data "ibm_is_subnet" "aspera" {
  name = var.vpc_subnet_name
}

data "ibm_is_image" "aspera" {
  name = var.aspera_base_image_name
}

data "ibm_is_ssh_key" "aspera" {
  name = var.ssh_key_name
}

data "ibm_is_security_groups" "vpc" {
  vpc_id = data.ibm_is_subnet.aspera.vpc
}

resource "ibm_iam_api_key" "temp" {
  name        = format("%s-tempkey", var.name)
  description = "API key created by power-aspera-server IaC"
}

locals {
  setup_script = templatefile(format("%s/%s", path.module, "scripts/setup.sh.tpl"), {
    ibmcloud_api_key        = ibm_iam_api_key.temp.apikey,
    ibmcloud_api_key_id     = ibm_iam_api_key.temp.apikey_id,
    cos_bucket_name         = var.cos_bucket_name,
    vpc_region              = var.ibmcloud_region,
    cos_region              = var.cos_region == "" ? var.ibmcloud_region : var.cos_region,
    nfs_mount_string        = var.nfs_mount_string,
    export_volume_directory = var.export_volume_directory
    vpc_subnet_cidr         = data.ibm_is_subnet.aspera.ipv4_cidr_block
  })
}

resource "ibm_is_instance_template" "new_volume" {
  count   = var.export_volume_size == 0 ? 0 : length(data.ibm_is_volumes.existing.volumes) == 1 ? 0 : 1
  name    = format("%s-%s", var.name, "new-volume")
  profile = var.vpc_instance_profile
  image   = data.ibm_is_image.aspera.id
  keys    = [data.ibm_is_ssh_key.aspera.id]
  primary_network_interface {
    subnet = data.ibm_is_subnet.aspera.id
  }
  volume_attachments {
    delete_volume_on_instance_delete = false
    # Name of the volume ATTACHMENT
    name = var.export_volume_name
    volume_prototype {
      # PROVIDER BUG: specifying name of volume not supported
      # name     = var.export_volume_name
      profile  = var.export_volume_profile
      capacity = var.export_volume_size
    }
  }
  zone = data.ibm_is_subnet.aspera.zone
  vpc  = data.ibm_is_subnet.aspera.vpc
}

resource "ibm_is_instance_template" "existing_volume" {
  count   = var.export_volume_size == 0 ? 0 : length(data.ibm_is_volumes.existing.volumes) == 1 ? 1 : 0
  name    = format("%s-%s", var.name, "new-volume")
  profile = var.vpc_instance_profile
  image   = data.ibm_is_image.aspera.id
  keys    = [data.ibm_is_ssh_key.aspera.id]
  primary_network_interface {
    subnet = data.ibm_is_subnet.aspera.id
  }
  volume_attachments {
    delete_volume_on_instance_delete = false
    volume                           = length(data.ibm_is_volumes.existing.volumes) == 1 ? data.ibm_is_volumes.existing.volumes[0].id : null
    name                             = length(data.ibm_is_volumes.existing.volumes) == 1 ? data.ibm_is_volumes.existing.volumes[0].name : null
  }
  zone = data.ibm_is_subnet.aspera.zone
  vpc  = data.ibm_is_subnet.aspera.vpc
}

resource "ibm_is_instance_template" "nfs_volume" {
  count   = var.nfs_mount_string == "" ? 0 : 1
  name    = format("%s-%s", var.name, "new-volume")
  profile = var.vpc_instance_profile
  image   = data.ibm_is_image.aspera.id
  keys    = [data.ibm_is_ssh_key.aspera.id]
  primary_network_interface {
    subnet = data.ibm_is_subnet.aspera.id
  }
  zone = data.ibm_is_subnet.aspera.zone
  vpc  = data.ibm_is_subnet.aspera.vpc
}

locals {
  instance_template = var.export_volume_size == 0 ? ibm_is_instance_template.nfs_volume[0] : length(data.ibm_is_volumes.existing.volumes) == 1 ? ibm_is_instance_template.existing_volume[0] : ibm_is_instance_template.new_volume[0]
}

resource "ibm_is_instance" "aspera" {
  lifecycle {
    ignore_changes       = all
    replace_triggered_by = [ibm_iam_api_key.temp]
    precondition {
      condition     = (var.nfs_mount_string != "" || var.export_volume_size > 0) && !(var.nfs_mount_string != "" && var.export_volume_size > 0)
      error_message = "You must supply EITHER an NFS mount OR an export volume size greater than 0."
    }
  }

  name              = var.name
  instance_template = local.instance_template.id
  primary_network_interface {
    subnet = data.ibm_is_subnet.aspera.id
    security_groups = [
      for sg in data.ibm_is_security_groups.vpc.security_groups : sg.id if contains(var.vpc_security_groups, sg.name)
    ]

    primary_ip {
      auto_delete = true
      address     = var.vpc_ip_address
    }
  }

  user_data = format("%s\n%s", "#cloud-config", yamlencode({
    write_files = [
      {
        content     = local.setup_script
        path        = "/tmp/setup.sh"
        permissions = "0755"
        owner       = "root"
      },
    ],
    runcmd = [
      "/tmp/setup.sh &> /var/log/aspera_setup.log"
    ]
  }))
}
