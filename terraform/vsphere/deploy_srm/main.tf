provider "vsphere" {
    user           = var.vsphere_user
    password       = var.vsphere_password
    vsphere_server = var.vsphere_server

    # If you have a self-signed cert
    allow_unverified_ssl = true
}

data "vsphere_datacenter" "datacenter" {
  name = var.vsphere_datacenter
}

data "vsphere_datastore" "datastore" {
  name          = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_resource_pool" "pool" {
  name          = var.vsphere_resource_pool
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_network" "network" {
  name          = var.vsphere_network
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

#data "vsphere_host" "host" {
#  name          = var.vsphere_host
 # datacenter_id = data.vsphere_datacenter.datacenter.id
#}

resource "vsphere_virtual_machine" "vmFromLocalOvf" {
  name = var.vsphere_vm_name
  folder = var.vsphere_folder
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id = data.vsphere_datastore.datastore.id
  datacenter_id = data.vsphere_datacenter.datacenter.id
  #host_system_id = data.vsphere_host.host.id

  wait_for_guest_net_timeout = 0
  wait_for_guest_ip_timeout = 0

  ovf_deploy {
    local_ovf_path = "/mnt/cdrom/bin/srm-va_OVF10.ovf"
    disk_provisioning = "thin"
    ip_protocol          = "IPV4"
    ip_allocation_policy = "STATIC_MANUAL"
    ovf_network_map = {
        "Network 1" = data.vsphere_network.network.id
    }
  }

  vapp {
    properties = {
      "varoot-password" = var.srm_varoot_password,
      "vaadmin-password" = var.srm_vaadmin_password,
      "dbpassword" = var.srm_dbpassword,
      "ntpserver" = "ntp.sfo.rainpole.io",
      "enable_sshd" = "True",
      "vami.hostname" = "sfo-m01-srm01.sfo.rainpole.io",
      "addrfamily" = "ipv4",
      "netmode"  = "static",
      "gateway"  = "172.28.211.1",
      "domain"  = "sfo.rainpole.io",
      "searchpath" = "sfo.rainpole.io,rainple.io",
      "DNS" = "172.28.211.4,172.28.211.5",
      "ip0" = "172.28.211.124",
      "netprefix0" = "24"
    }
  }
}