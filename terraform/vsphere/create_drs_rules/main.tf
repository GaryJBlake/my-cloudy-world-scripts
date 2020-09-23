provider "vsphere" {
    user           = var.vsphere_user
    password       = var.vsphere_password
    vsphere_server = var.vsphere_server

    # If you have a self-signed cert
    allow_unverified_ssl = true
}

data "vsphere_datacenter" "dc" {
    name = var.vsphere_datacenter
}

data "vsphere_compute_cluster" "cluster" {
    name          = var.vsphere_cluster
    datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "vm" {
    name = var.virtual_machine
    datacenter_id = data.vsphere_datacenter.dc.id
}

resource "vsphere_compute_cluster_vm_anti_affinity_rule" "cluster_vm_host_rule" {
    name                    = var.vsphere_anti_affinity_rule
    compute_cluster_id      = data.vsphere_compute_cluster.cluster.id
    virtual_machine_ids     = data.vsphere_virtual_machine.vm[*].id
}
