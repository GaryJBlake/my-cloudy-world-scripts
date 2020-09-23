provider "vsphere" {
    user           = var.vsphere_user
    password       = var.vsphere_password
    vsphere_server = var.vsphere_server

    # If you have a self-signed cert
    allow_unverified_ssl = true
}

resource "vsphere_tag_category" "category" {
    name        = var.vsphere_tag_category
    cardinality = "SINGLE"
    description = var.vsphere_description

    associable_types = [
        "Datastore",
    ]
}

resource "vsphere_tag" "tag" {
    name        = var.vsphere_tag
    category_id = vsphere_tag_category.category.id
    description = var.vsphere_description
}