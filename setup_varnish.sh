#!/bin/bash
set -euo pipefail

# === CONFIGURATION ===
EMAIL="your-email@example.com"   # Replace this!
CERTBOT_DOMAIN_FALLBACK="example.com"

# === STEP 1: Install dependencies ===
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  curl dnsutils certbot hitch stunnel4

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

# === STEP 8: Start services ===
echo "🚀 Starting stunnel and hitch..."
systemctl restart stunnel4
systemctl restart hitch

echo "🎉 Setup complete. TLS terminator running for $FQDN"
