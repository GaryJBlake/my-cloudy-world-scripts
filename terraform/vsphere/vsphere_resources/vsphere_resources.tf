##################################################################################
# VARIABLES
##################################################################################

variable "vsphere_user" {}
variable "vsphere_password" {}
variable "vsphere_server" {}
variable "vsphere_datacenter" {}
variable "vsphere_cluster" {}


##################################################################################
# PROVIDERS
##################################################################################

provider "vsphere" {
  user           = var.vsphere_user
  password       = var.vsphere_password
  vsphere_server = var.vsphere_server
  allow_unverified_ssl = true # if you have a self-signed cert
}

##################################################################################
# DATA
##################################################################################



##################################################################################
# RESOURCES
##################################################################################

resource "vsphere_datacenter" "ds_datacenter" {
  name = var.vsphere_datacenter
}

resource "vsphere_compute_cluster" "ds_cluster" {
  name                      = var.vsphere_cluster
  datacenter_id             = ds_datacenter.id

  drs_enabled               = true
  drs_automation_level      = "fullyAutomated"
  ha_enabled                = true
}

##################################################################################
# OUTPUT
##################################################################################

output "ds_datacenter" {
  value         = vsphere_datacenter.ds_datacenter.id
}

output "ds_cluster" {
  value         = vsphere_compute_cluster.ds_cluster.*
}