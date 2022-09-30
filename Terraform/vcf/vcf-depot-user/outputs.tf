##################################################################################
# OUTPUTS
##################################################################################

output "vcf_depot_message" {
  value = jsondecode(terracurl_request.vcf_depot_user.response).vmwareAccount.message
}

output "vcf_depot_status" {
  value = jsondecode(terracurl_request.vcf_depot_user.response).vmwareAccount.status
}