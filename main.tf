terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 2.6"
    }
  }
}

provider "linode" {
  token = var.linode_token
}

locals {
  varnish_public_ips = [
    for instance in linode_instance.varnish : 
    one([
      for ip in instance.ipv4 :
      ip if !startswith(ip, "192.") && !startswith(ip, "10.") && !startswith(ip, "172.")
    ])
  ]
}

resource "linode_instance" "varnish" {
  count       = var.varnish_nodes
  label       = "varnish1-${count.index}"
  image       = "linode/ubuntu22.04"
  region      = var.region
  type        = "g6-standard-2"
  root_pass   = var.root_pass
  private_ip  = true
  authorized_keys = split("\n", trimspace(file(var.public_key_path)))
  tags        = ["varnish-cluster"]
}

resource "null_resource" "configure_varnish" {
  count = var.varnish_nodes

connection {
  type        = "ssh"
  host        = local.varnish_public_ips[count.index]
  user        = "root"
  private_key = file(var.private_key_path)
  timeout     = "2m"
}

  provisioner "file" {
    source      = "setup_varnish.sh"
    destination = "/root/setup_varnish.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /root/setup_varnish.sh",
      "/root/setup_varnish.sh ${count.index} ${join(" ", linode_instance.varnish[*].private_ip_address)}"
    ]
  }

  depends_on = [linode_instance.varnish]
}

output "private_ips" {
  value = linode_instance.varnish[*].private_ip_address
}
