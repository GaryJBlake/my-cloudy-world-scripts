##################################################################################
# VARIABLES
##################################################################################

# VMware Cloud Console Endpoint

variable "csp_uri" {
  type        = string
  description = "Base URL for VMware Cloud Service. (e.g. https://console.cloud.vmware.com)"
  default     = "https://console.cloud.vmware.com"
}

variable "csp_api_token" {
  type        = string
  description = "API token for theVMware Cloud Service endpoint."
}

variable "debug" {
  type        = bool
  description = "Enable debugging"
  default     = false
}

# vRealize Automation Cloud Endpoint

variable "vra_uri" {
  type        = string
  description = "The base URL of the vRealize Automation endpoint. (e.g. https://api.mgmt.cloud.vmware.com)"
  default     = "https://api.mgmt.cloud.vmware.com"
}

variable "vra_insecure" {
  type        = bool
  description = "Set to true for self-signed certificates."
  default     = false
}

variable "cloud_proxy_name" {
  type        = string
  description = "Name of the Cloud Extensibility Proxy. (e.g. sfo-vmc-cep01)"
}

variable "vro_integration_name" {
  type        = string
  description = "Name of the vRO Integration. (e.g. sfo-w01-vro-integration)"
}