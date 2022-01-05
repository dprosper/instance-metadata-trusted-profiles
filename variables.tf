variable "ibmcloud_api_key" {
  description = "IBM API key. Refer https://cloud.ibm.com/docs/account?topic=account-userapikey&interface=ui"
}

variable "resource_group_name" {
  description = "Resource group name."
  default = "default"
}

variable "basename" {
  description = "Prefix used for all resource names"
  default = "ci"
}

variable "ibmcloud_timeout" {
  description = "Timeout for API operations in seconds."
  default     = 900
}

variable "region" {
  default     = "us-east"
  description = "For supported regions, refer https://cloud.ibm.com/docs/overview?topic=overview-locations"
}

variable "vsi_image_name" {
  default     = "ibm-ubuntu-20-04-2-minimal-amd64-1"
  description = "Ubuntu 20.04 images only"
}

variable "cycle_wait_seconds" {
  description = "Used to determine the wait time for the service deployed on the instance to check for an update SSH keys."
  default     = 900
}