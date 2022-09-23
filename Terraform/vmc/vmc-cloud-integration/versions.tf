##################################################################################
# VERSIONS
##################################################################################

terraform {
  required_providers {
    vra = {
      source  = "vmware/vra"
      version = ">= 0.5.3"
    }
    terracurl = {
      source  = "devops-rob/terracurl"
      version = "0.1.0"
    }
  }
  required_version = ">= 1.2.0"
}