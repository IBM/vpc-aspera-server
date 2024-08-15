##############################################################################
# Terraform Outputs
##############################################################################

locals {
  aspera_private_ip = ibm_is_instance.aspera.primary_network_interface[0].primary_ip[0].address
}

output "aspera_endpoint" {
  description = "Aspera server endpoint for data transfer."
  value       = local.aspera_private_ip
}

output "aspera_nfs_mount" {
  description = "Mount point for exported volume."
  value       = var.export_volume_size == 0 ? "" : format("%s:%s", local.aspera_private_ip, var.export_volume_directory)
}
