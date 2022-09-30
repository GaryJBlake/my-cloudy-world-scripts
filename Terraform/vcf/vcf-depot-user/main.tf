##################################################################################
# PROVIDERS
##################################################################################

provider "terracurl" {
  # Configuration options
}

##################################################################################
# DATA
##################################################################################


##################################################################################
# RESOURCES
##################################################################################

resource "terracurl_request" "vcf_access_token" {
  name           = "vcf_access_token"
  url            = "https://${var.vcf_instance}/v1/tokens"
  method         = "POST"
  response_codes = [200,401]
  headers = {
    Accept       = "application/json"
    Content-Type = "application/json"
  }

  request_body = <<EOF
{
  "username": "${var.vcf_username}",
  "password": "${var.vcf_password}"
}
EOF
}

resource "terracurl_request" "vcf_depot_user" {
  name           = "vcf_depot_user"
  url            = "https://${var.vcf_instance}/v1/system/settings/depot"
  method         = "PUT"
  response_codes = [201,202,401]
  headers = {
    Accept        = "application/json"
    Content-Type  = "application/json"
    Authorization = "Bearer ${jsondecode(terracurl_request.vcf_access_token.response).accessToken}"
  }

  request_body = <<EOF
{
  "vmwareAccount": {
    "username": "${var.depot_user}",
    "password": "${var.depot_password}"
  }
}
EOF
}
