# Configure the VMware NSX-T Provider

provider "nsxt" {
  host                  = var.nsx_manager
  username              = var.nsx_username
  password              = var.nsx_password
  allow_unverified_ssl  = true
  max_retries           = 10
  retry_min_delay       = 500
  retry_max_delay       = 5000
  retry_on_status_codes = [429]
}

data "nsxt_policy_tier0_gateway" "tier0_gw_gateway" {
  display_name = "sfo-m01-ec01-t0-gw01"
} 
