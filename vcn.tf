# Copyright (c) 2019, 2022 Oracle Corporation and/or affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

resource "oci_core_vcn" "vcn" {
  # We still allow module users to declare a cidr using `vcn_cidr` instead of the now recommended `vcn_cidrs`, but internally we map both to `cidr_blocks`
  # The module always use the new list of string structure and let the customer update his module definition block at his own pace.
  cidr_blocks    = var.vcn_cidrs[*]
  compartment_id = var.compartment_id
  display_name   = var.label_prefix == "none" ? var.vcn_name : "${var.label_prefix}-${var.vcn_name}"
  dns_label      = var.vcn_dns_label
  is_ipv6enabled = var.enable_ipv6

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags

  lifecycle {
    ignore_changes = [defined_tags, dns_label, freeform_tags]
  }
}

#Module for Subnet
module "subnet" {
  source = "./modules/subnet"

  compartment_id = var.compartment_id
  tenancy_id     = var.tenancy_id
  subnets        = var.subnets
  enable_ipv6    = var.enable_ipv6
  vcn_id         = oci_core_vcn.vcn.id
  ig_route_id    = var.create_internet_gateway ? oci_core_route_table.ig[0].id : null
  nat_route_id   = var.create_nat_gateway ? oci_core_route_table.nat[0].id : null
  security_list_ids = [oci_core_security_list.public_security_list.id]
  freeform_tags = var.freeform_tags

  count = length(var.subnets) > 0 ? 1 : 0

}


locals {
  vcn_id = oci_core_vcn.vcn.id
  subnet = {
    for key, value in var.subnets : key => contains(keys(value), "name") ? value.name : key
  }
  service_logdef = { for k in local.subnet : format("%s_%s", k, "log") => { loggroup = "loggrp", service = "flowlogs", resource = k } }
}

#Module for Logging
module "logging" {

  count  = var.enable_vcn_logging ? 1 : 0
  source = "github.com/oracle-terraform-modules/terraform-oci-logging"

  compartment_id         = var.compartment_id
  log_retention_duration = var.log_retention_duration
  service_logdef         = local.service_logdef
  vcn_id                 = local.vcn_id
  tenancy_id             = var.tenancy_id

  depends_on = [
    oci_core_vcn.vcn,
    module.subnet
  ]
}
