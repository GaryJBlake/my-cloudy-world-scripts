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
  response_codes = [200, 401]
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

resource "terracurl_request" "vcf_create_microsoft_ca" {
  name           = "vcf_create_microsoft_ca"
  url            = "https://${var.vcf_instance}/v1/certificate-authorities"
  method         = "PUT"
  response_codes = [200, 400, 500]
  headers = {
    Accept        = "application/json"
    Content-Type  = "application/json"
    Authorization = "Bearer ${jsondecode(terracurl_request.vcf_access_token.response).accessToken}"
  }

  request_body = <<EOF
{
  "microsoftCertificateAuthoritySpec": {
      "secret": "${var.ca_password}",
      "serverUrl": "${var.ca_server_url}",
      "username": "${var.ca_username}",
      "templateName": "${var.ca_template}"
    }
}
EOF

  destroy_url    = "https://${var.vcf_instance}/v1/certificate-authorities/Microsoft"
  destroy_method = "DELETE"
  destroy_headers = {
    Accept        = "application/json"
    Content-Type  = "application/json"
    Authorization = "Bearer ${jsondecode(terracurl_request.vcf_access_token.response).accessToken}"
  }

  destroy_response_codes = [200]
}
