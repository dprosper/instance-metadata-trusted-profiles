#  Retrieve information of an existing IBM Cloud Infrastructure image as a read-only data source.
data "ibm_is_image" "vsi_image" {
  name = var.vsi_image_name
}

# Retrieve information about an existing IBM resource group as a read-only data source. 
data "ibm_resource_group" "group" {
  name = var.resource_group_name
}

# Create a Virtual Private Cloud (VPC).              
resource "ibm_is_vpc" "vpc" {
  name           = "${var.basename}-vpc"
  resource_group = data.ibm_resource_group.group.id
}

# Create a Virtual Private Cloud (VPC) Subnet in one region.
resource "ibm_is_subnet" "subnet" {
  name                     = "${var.basename}-subnet"
  vpc                      = ibm_is_vpc.vpc.id
  zone                     = "${var.region}-1"
  resource_group           = data.ibm_resource_group.group.id
  total_ipv4_address_count = 16
}

# Create a Virtual Private Cloud (VPC) Security Group that will be applied to a VSI Network Interface.
resource "ibm_is_security_group" "group" {
  name           = "${var.basename}-group"
  resource_group = data.ibm_resource_group.group.id
  vpc            = ibm_is_vpc.vpc.id
}

# Create a Virtual Private Cloud (VPC) Security Group rule for allowing port 80 (http) egress.
resource "ibm_is_security_group_rule" "tcp_80" {
  group     = ibm_is_security_group.group.id
  direction = "outbound"
  remote    = "0.0.0.0/0"

  tcp {
    port_min = 80
    port_max = 80
  }
}

# Create a Virtual Private Cloud (VPC) Security Group rule for allowing port 443 (https) egress.
resource "ibm_is_security_group_rule" "tcp_443" {
  group     = ibm_is_security_group.group.id
  direction = "outbound"
  remote    = "0.0.0.0/0"

  tcp {
    port_min = 443
    port_max = 443
  }
}

# Create a Virtual Private Cloud (VPC) Security Group rule for allowing port 53 (dns) egress.
resource "ibm_is_security_group_rule" "tcp_53" {
  group     = ibm_is_security_group.group.id
  direction = "outbound"
  remote    = "0.0.0.0/0"

  tcp {
    port_min = 53
    port_max = 53
  }
}

# Create a Virtual Private Cloud (VPC) Security Group rule for allowing port 53 (dns) egress.
resource "ibm_is_security_group_rule" "udp_443" {
  group     = ibm_is_security_group.group.id
  direction = "outbound"
  remote    = "0.0.0.0/0"

  udp {
    port_min = 53
    port_max = 53
  }
}

# Create a Virtual Private Cloud (VPC) Security Group rule for allowing port 22 (ssh) ingress.
resource "ibm_is_security_group_rule" "ssh" {
  group     = ibm_is_security_group.group.id
  direction = "inbound"
  remote    = "0.0.0.0/0"

  tcp {
    port_min = 22
    port_max = 22
  }
}