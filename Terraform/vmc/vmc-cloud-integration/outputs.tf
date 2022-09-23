##################################################################################
# OUTPUTS
##################################################################################

output "output_cloud_proxy" {
  value = data.vra_data_collector.cloud_proxy
}

output "output_vro_integration_name" {
  value = terracurl_request.create_vro_integration.name
}

output "output_vro_integration_response" {
  value = jsondecode(terracurl_request.create_vro_integration.response).selfLink
}