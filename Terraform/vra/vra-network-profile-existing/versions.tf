##################################################################################
# VERSIONS
##################################################################################

terraform {
  required_providers {
    vra = {
      source  = "vmware/vra"
      version = ">= 0.3.8"
    }
  }
  required_version = ">= 1.0.0"
}