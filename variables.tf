variable "linode_token" {
  type        = string
  description = "Linode API Token"
}

variable "root_pass" {
  type        = string
  description = "Root password for VMs"
  sensitive   = true
}

variable "region" {
  default = "us-ord"
}

variable "varnish_nodes" {
  default = 3
}
