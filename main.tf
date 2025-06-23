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

resource "linode_instance" "varnish" {
  count       = var.varnish_nodes
  label       = "varnish-${count.index}"
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
  host        = element([
    for ip in linode_instance.varnish[count.index].ipv4 :
    ip if !startswith(ip, "192.") && !startswith(ip, "10.") && !startswith(ip, "172.")
  ], 0)
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
