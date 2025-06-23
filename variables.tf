variable "linode_token" {
  type        = string
  description = "Your Linode API Token"
}

variable "root_pass" {
  type        = string
  description = "Root password for Linodes"
  sensitive   = true
}

variable "public_key_path" {
  description = "Path to your SSH public key"
  default     = "~/.ssh/id_rsa.pub"
}

variable "private_key_path" {
  description = "Path to your SSH private key"
  default     = "~/.ssh/id_rsa"
}

variable "region" {
  default = "us-east"
}

variable "varnish_nodes" {
  default = 3
}

