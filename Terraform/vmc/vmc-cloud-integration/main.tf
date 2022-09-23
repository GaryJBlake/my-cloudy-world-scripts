##################################################################################
# PROVIDERS
##################################################################################

provider "vra" {
  url           = var.vra_uri
  refresh_token = var.csp_api_token
  insecure      = var.vra_insecure
}

provider "terracurl" {
  # Configuration options
}

# ##################################################################################
# DATA
# ##################################################################################

data "vra_data_collector" "cloud_proxy" {
  name = var.cloud_proxy_name
}

data "tls_certificate" "example_content" {
  depends_on   = [data.vra_data_collector.cloud_proxy]
  url          = "https://${data.vra_data_collector.cloud_proxy.hostname}"
  verify_chain = false
}

# ##################################################################################
# RESOURCES
# ##################################################################################

# Obtain Access Token from VMware Cloud Service
resource "terracurl_request" "get_access_token" {
  name           = "access_token"
  url            = "${var.csp_uri}/csp/gateway/am/api/auth/api-tokens/authorize?refresh_token=${var.csp_api_token}"
  method         = "POST"
  response_codes = [200, 400, 404, 409, 429, 500]
  headers = {
    Content-Type = "application/x-www-form-urlencoded"
  }

  destroy_response_codes = []
  destroy_url            = ""
  destroy_method         = ""

  lifecycle {
    ignore_changes = [ # Items to be ignored when re-applying a plan

    ]
  }
}

resource "terracurl_request" "create_vro_integration" {
  depends_on = [
    terracurl_request.get_access_token,
    data.vra_data_collector.cloud_proxy
  ]
  name           = "vro_integration"
  url            = "${var.vra_uri}/iaas/api/integrations?apiVersion=2021-07-15"
  method         = "POST"
  response_codes = [202, 400, 403]
  headers = {
    Accept        = "application/json"
    Content-Type  = "application/json"
    Authorization = "Bearer ${jsondecode(terracurl_request.get_access_token.response).access_token}"
  }
  request_body = <<EOF
{
	"certificateInfo": {
		"certificate": "${data.tls_certificate.example_content.certificates[0].cert_pem}"
	},
	"customProperties": {
		"endpointEnabled": true
	},
	"integrationProperties": {
		"acceptSelfSignedCertificate": false,
		"dcId": "${data.vra_data_collector.cloud_proxy.id}",
		"hostName": "https://${data.vra_data_collector.cloud_proxy.hostname}:443",
		"privateKey": "",
		"privateKeyId": "",
		"refreshToken": "${var.csp_api_token}",
		"vroAuthType": "CSP"
	},
	"integrationType": "vro",
	"name": "${var.vro_integration_name}",
	"privateKey": "",
	"privateKeyId": "",
  "tags": [
    {
      "key": "integration",
      "value": "prod"
    }
  ]
}
EOF

  destroy_response_codes = [202, 204, 403]
  destroy_url            = ""
  destroy_method         = ""
}
