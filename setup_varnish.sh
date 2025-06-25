#!/bin/bash
set -euo pipefail

# === CONFIGURATION ===
EMAIL=""   # Replace this!
CERTBOT_DOMAIN_FALLBACK="example.com"
NODE_INDEX=$1
shift
IPS=("$@")

# === STEP 1: Install dependencies ===
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  curl dnsutils certbot hitch stunnel4 varnish

# === STEP 2: Resolve FQDN ===
PUBLIC_IP=$(curl -s https://api.ipify.org)
FQDN=$(dig +short -x "$PUBLIC_IP" | sed 's/\.$//' || true)

if [[ -z "$FQDN" ]]; then
  echo "⚠️  Could not determine FQDN via reverse DNS. Falling back to $CERTBOT_DOMAIN_FALLBACK"
  FQDN="$CERTBOT_DOMAIN_FALLBACK"
fi

echo "🌐 Using FQDN: $FQDN"

# === STEP 3: Stop Hitch if running ===
systemctl stop hitch || true
pkill hitch || true

# === STEP 4: Request/renew Let's Encrypt cert ===
echo "🔐 Requesting Let's Encrypt certificate..."
certbot certonly --standalone --non-interactive --agree-tos -m "$EMAIL" -d "$FQDN"

# === STEP 5: Prepare Hitch-compatible PEM file ===
CERT_PATH="/etc/letsencrypt/live/$FQDN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$FQDN/privkey.pem"
HITCH_PEM="/etc/hitch/hitch.pem"

if [[ ! -f "$CERT_PATH" || ! -f "$KEY_PATH" ]]; then
  echo "❌ Certificate files not found after certbot. Exiting."
  exit 1
fi

cat "$CERT_PATH" "$KEY_PATH" > "$HITCH_PEM"
chown _hitch:_hitch "$HITCH_PEM"
chmod 600 "$HITCH_PEM"

# === STEP 6: Configure Hitch ===
cat <<EOF > /etc/hitch/hitch.conf
frontend = "[0.0.0.0]:443"
backend = "[127.0.0.1]:6081"
pem-file = "$HITCH_PEM"
user = "_hitch"
group = "_hitch"
write-proxy-v2 = on
EOF

echo "✅ Hitch config written."

# === STEP 7: Configure and launch stunnel ===
cat <<EOF > /etc/stunnel/stunnel.conf
foreground = yes
client = yes
verifyChain = no
verifyPeer = no

[foil]
client = yes
accept = 127.0.0.1:8443
connect = foil.aiv.vpg.apple.com:443

[sabre]
client = yes
accept = 127.0.0.1:8444
connect = sabre.aiv.vpg.apple.com:443
EOF

# Enable stunnel service
sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4

echo "✅ Stunnel config written."

# === STEP 8: Enable and start services ===
systemctl enable varnish
systemctl enable hitch
systemctl enable stunnel4

systemctl restart stunnel4 --no-block || systemctl restart stunnel4 </dev/null
systemctl restart hitch

# === STEP 9: Configure Varnish backends ===
cat <<EOF > /etc/varnish/default.vcl
vcl 4.1;

import directors;

backend foil_backend {
    .host = "127.0.0.1";
    .port = "8443";
}

backend sabre_backend {
    .host = "127.0.0.1";
    .port = "8444";
}

EOF

# Define Varnish cluster backends
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

cat <<'EOF' >> /etc/varnish/default.vcl

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

cat <<'EOF' >> /etc/varnish/default.vcl
}

sub vcl_recv {
    if (req.http.host == "foil.aiv.vpg.apple.com") {
        set req.backend_hint = foil_backend;
    } elseif (req.http.host == "sabre.aiv.vpg.apple.com") {
        set req.backend_hint = sabre_backend;
    } else {
        set req.backend_hint = cluster.backend();
    }

    if (req.http.Access-Token) {
        set req.http.Access-Token-Copy = req.http.Access-Token;
    }

    set req.http.X-Orig-Host = req.http.host;
}

sub vcl_backend_fetch {
    if (bereq.http.X-Orig-Host) {
        set bereq.http.Host = bereq.http.X-Orig-Host;
    }

    if (bereq.http.Access-Token-Copy) {
        set bereq.http.Access-Token = bereq.http.Access-Token-Copy;
    }
}

sub vcl_backend_response {
    if (bereq.url ~ "\.m3u8$") {
        set beresp.ttl = 5s;
    } elseif (bereq.url ~ "\.m4s$" || bereq.url ~ "\.ts$") {
        set beresp.ttl = 60s;
    }
}

sub vcl_deliver {
    unset resp.http.Access-Token-Copy;
    unset resp.http.X-Orig-Host;
}
EOF

# Restart Varnish
systemctl restart varnish

echo "🎉 Varnish + TLS setup complete for $FQDN"
