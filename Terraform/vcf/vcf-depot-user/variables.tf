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

variable "depot_user" {
  type        = string
  description = "The user account to authenticate to the SDDC Manager online depot."
}

variable "depot_password" {
  type        = string
  description = "The password for the user to authenticate to the SDDC Manager online depot."
  sensitive   = true
}
