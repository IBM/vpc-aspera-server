##############################################################################
# Account Variables
##############################################################################

variable "ibmcloud_api_key" {
  description = "The IBM Cloud platform API key needed to deploy IAM enabled resources"
  type        = string
  sensitive   = true
}

variable "ibmcloud_region" {
  description = "IBM Cloud region where all resources will be deployed"
  type        = string

  validation {
    error_message = "Must use an IBM Cloud region. Use `ibmcloud regions` with the IBM Cloud CLI to see valid regions."
    condition = contains([
      "au-syd",
      "jp-tok",
      "eu-de",
      "eu-gb",
      "us-south",
      "us-east",
      "ca-tor",
      "jp-osa",
      "br-sao"
    ], var.ibmcloud_region)
  }
}

variable "vpc_subnet_name" {
  description = "Existing VPC network subnet name the Aspera server will be attached to."
  type        = string
}

variable "ssh_key_name" {
  description = <<-EOD
    SSH key for the Aspera Server. This key must exist in the VPC.
    It is used for root SSH access as well as the Aspera connection.
  EOD
  type        = string
}

variable "name" {
  description = <<-EOD
    The name used for the Aspera server.
    Other resources created will use this for their basename and be suffixed by a random identifier.
  EOD
  type        = string
}

variable "cos_region" {
  description = <<-EOD
    Optional variable to specify the region the COS bucket resides in.

    Available regions are: jp-osa, jp-tok, eu-de, eu-gb, ca-tor, us-south, us-east, and br-sao.
    Please see [Regions](https://cloud.ibm.com/docs/overview?topic=overview-locations) for an updated list.

    If not specified, the region corresponding to the `ibmcloud_region` will be used.
  EOD
  type        = string
  default     = ""
}

variable "cos_bucket_name" {
  description = "COS bucket that contains the Aspera installer and license file."
  type        = string
}

variable "nfs_mount_string" {
  description = <<-EOD
    Either `nfs_mount_string` or `export_volume_size` MUST be specified.

    This will specify the NFS mount string in the format `<IP>:<shared directory>`
    Used for the Aspera destination.
  EOD
  type        = string
  default     = ""
}

variable "export_volume_name" {
  description = "Optional variable for name for volume created to export."
  type        = string
  default     = "aspera"
}

variable "export_volume_profile" {
  description = <<-EOD
    Optional variable for the type of disk for volume created to export.
    Supported values are `general-purpose`, `5iops-tier`, `10iops-tier`."
  EOD
  type        = string
  default     = "general-purpose"
}

variable "export_volume_size" {
  description = <<-EOD
    Either `nfs_mount_string` or `export_volume_size` MUST be specified.

    Size of disk in GB for volume created to export.
    If specified, the disk size must be between 10 and 16000 GB.
    When greater than 0, Aspera will use this as the destination instead of the `nfs_mount_string`.
    When equal to 0, volume is not created and Aspera will use `nfs_mount_string` as its destination.
    The export volume will be exported as an NFS share.
  EOD
  type        = number
  default     = 0

  validation {
    error_message = "Export volume size must be between 10 and 16000 or 0 for NFS mount."
    condition     = (var.export_volume_size == 0 || (var.export_volume_size >= 10 && var.export_volume_size <= 16000))
  }
}

variable "export_volume_directory" {
  description = "Optional variable for directory used for export volume. Must be absolute."
  type        = string
  default     = "/aspera"
}

variable "vpc_instance_profile" {
  description = "Optional variable to set instance cores and memory by VSI Profile."
  type        = string
  default     = "bx2-2x8"
}

variable "vpc_ip_address" {
  description = <<-EOD
    Optional variable to statically set the private network IP address for the Aspera server.
    The default behavior is to randomly assign an IP from the `vpc_subnet_name` network.
  EOD
  type        = string
  default     = ""
}

variable "vpc_security_groups" {
  description = <<-EOD
    Optional security groups for the Aspera VSI.
    The default security group for the VPC `vpc_subnet_name` is in will be used otherwise.
  EOD
  type        = list(string)
  default     = []
}

variable "aspera_base_image_name" {
  description = <<-EOD
    Debug variable to specify the base OS for the Aspera server.
    This Aspera server automation has been tested with CentOS 9 Stream (VPC version 7).
    Use this variable if you wish to try another version.
  EOD
  type        = string
  default     = "ibm-centos-stream-9-amd64-7"
}
