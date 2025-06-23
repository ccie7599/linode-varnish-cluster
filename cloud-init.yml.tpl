#cloud-config
package_update: true
package_upgrade: true
packages:
  - varnish

write_files:
  - path: /etc/varnish/default.vcl
    permissions: '0644'
    content: |
      vcl 4.1;

      import directors;

      backend local {
          .host = "127.0.0.1";
          .port = "8080";
      }

      sub vcl_init {
          new cluster = directors.round_robin();
%{ for i, label in labels ~}
%{ if i != node_index ~}
          cluster.add_backend(backend_${label});
%{ endif ~}
%{ endfor ~}
      }

%{ for i, label in labels ~}
%{ if i != node_index ~}
      backend backend_${label} {
          .host = "${private_ips[i]}";
          .port = "80";
      }
%{ endif ~}
%{ endfor ~}

      sub vcl_recv {
          set req.backend_hint = cluster.backend();
      }

runcmd:
  - systemctl restart varnish
