#!/bin/bash

set -euo pipefail

NODE_INDEX=$1
shift
IPS=("$@")

# Ensure APT is not locked or running elsewhere
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 ; do
  echo "Waiting for APT lock to release..."
  sleep 2
done

apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y varnish

cat <<EOF > /etc/varnish/default.vcl
vcl 4.1;

import directors;
EOF

# Define backends first
i=0
for ip in "${IPS[@]}"; do
  if [ "$i" -ne "$NODE_INDEX" ]; then
    cat <<EOF >> /etc/varnish/default.vcl
backend backend$i {
  .host = "$ip";
  .port = "80";
}
EOF
  fi
  i=$((i+1))
done

# Now define vcl_init and use them
cat <<EOF >> /etc/varnish/default.vcl

sub vcl_init {
    new cluster = directors.round_robin();
EOF

i=0
for ip in "${IPS[@]}"; do
  if [ "$i" -ne "$NODE_INDEX" ]; then
    echo "    cluster.add_backend(backend$i);" >> /etc/varnish/default.vcl
  fi
  i=$((i+1))
done

cat <<EOF >> /etc/varnish/default.vcl
}

sub vcl_recv {
  set req.backend_hint = cluster.backend();
}
EOF

# Restart Varnish
systemctl restart varnish
