##################################################################################
# VARIABLES
##################################################################################

variable "vcf_instance" {
  type        = string
  description = "The fully qualified domain name or IP address of the SDDC Manager instance. (e.g. sfo-vcf01.sfo.rainpole.io)"
}

variable "vcf_username" {
  type        = string
  description = "The username to authenticate to the SDDC Manager instance. (e.g. admin)"
  default     = "admin"
}

variable "vcf_password" {
  type        = string
  description = "The password for the user to authenticate with to the SDDC Manager instance."
  sensitive   = true
}

variable "ca_server_url" {
  type        = string
  description = "The server URL for the Microsoft Certificate Authority. (e.g. https://rpl-dc01.rainpole.io/certsrv)"
}

variable "ca_username" {
  type        = string
  description = "The service account for connecting to the Microsoft Certificate Authority."
}

variable "ca_password" {
  type        = string
  description = "The password for service account for connecting to the Microsoft Certificate Authority."
  sensitive   = true
}

variable "ca_template" {
  type        = string
  description = "The name of the Microsoft Certificate Authority template to use. (e.g. VMware)"
}