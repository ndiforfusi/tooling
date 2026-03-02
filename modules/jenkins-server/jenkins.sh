#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

DOMAIN="jenkins.nchanjicasey.com"
ADMIN_EMAIL="alaintonfack167@gmail.com"

echo "[1/7] Base packages & Java 21"
# Jenkins documentation now recommends Java 21
apt-get update -y
apt-get install -y curl gnupg ca-certificates lsb-release fontconfig openjdk-21-jre dnsutils

echo "[2/7] Jenkins repo & install"
# Clean up any legacy configurations
rm -f /etc/apt/sources.list.d/jenkins.list

# Use the updated 2026 key and modern keyring path
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key | gpg --dearmor -o /etc/apt/keyrings/jenkins-keyring.gpg --yes

# Create the repository list pointing to the new GPG key
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.gpg] https://pkg.jenkins.io/debian-stable binary/" \
  | tee /etc/apt/sources.list.d/jenkins.list >/dev/null

apt-get update -y
apt-get install -y jenkins
systemctl enable --now jenkins

echo "[3/7] Nginx + Certbot"
apt-get install -y nginx certbot python3-certbot-nginx
rm -f /etc/nginx/sites-enabled/default

echo "[4/7] Nginx HTTP reverse proxy"
tee /etc/nginx/sites-available/jenkins.conf >/dev/null <<'EOL'
server {
    listen 80;
    listen [::]:80;
    server_name jenkins.nchanjicasey.com;

    client_max_body_size 512m;
    proxy_read_timeout 300;
    proxy_connect_timeout 60;
    proxy_send_timeout 300;

    location / {
        proxy_pass         http://127.0.0.1:8080;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_set_header   X-Forwarded-Port  $server_port;

        proxy_http_version 1.1;
        proxy_set_header   Upgrade           $http_upgrade;
        proxy_set_header   Connection        "upgrade";
        proxy_redirect     off;
    }
}
EOL

ln -sfn /etc/nginx/sites-available/jenkins.conf /etc/nginx/sites-enabled/jenkins.conf
nginx -t
systemctl reload nginx

echo "[5/7] Skipping local firewall (using AWS Security Groups)"

echo "[6/7] Install background DNS-to-HTTPS job"
cat >/usr/local/bin/issue-cert-when-dns-ready.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

DOMAIN="jenkins.nchanjicasey.com"
ADMIN_EMAIL="alaintonfack167@gmail.com"
MAX_TRIES=240
SLEEP_SECS=30

log() { echo "[issue-cert] $*"; }

# Get public IP using AWS IMDSv2 (Standard for modern EC2)
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PUBIP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/public-ipv4)

if [ -z "$PUBIP" ]; then
  log "Public IP not found. Ensure the instance has an Elastic IP."
  exit 0
fi

log "Instance IP: $PUBIP. Waiting for DNS resolution..."

i=0
while :; do
  DNSIP="$(dig +short ${DOMAIN} A | head -n1 || true)"
  if [ -n "$DNSIP" ] && [ "$DNSIP" = "$PUBIP" ]; then
    log "DNS verified. Requesting SSL certificate..."
    break
  fi
  i=$((i+1))
  [ "$i" -ge "$MAX_TRIES" ] && exit 0
  sleep "$SLEEP_SECS"
done

# Ensure Jenkins service is fully up before proceeding
until curl -s http://127.0.0.1:8080/login | grep -q "Jenkins"; do sleep 5; done

certbot --nginx -d "$DOMAIN" -m "$ADMIN_EMAIL" --agree-tos --no-eff-email --non-interactive --redirect
systemctl reload nginx
SCRIPT

chmod +x /usr/local/bin/issue-cert-when-dns-ready.sh

# Background Poller via Systemd
cat >/etc/systemd/system/issue-cert.service <<'UNIT'
[Unit]
Description=Certbot DNS Poller
After=network-online.target nginx.service jenkins.service
[Service]
Type=oneshot
ExecStart=/usr/local/bin/issue-cert-when-dns-ready.sh
UNIT

cat >/etc/systemd/system/issue-cert.timer <<'TIMER'
[Unit]
Description=Run Certbot Poller on Boot
[Timer]
OnBootSec=1m
Unit=issue-cert.service
[Install]
WantedBy=timers.target
TIMER

systemctl daemon-reload
systemctl enable --now issue-cert.timer

echo "[7/7] Final status check"
systemctl status jenkins --no-pager | head -n 12

echo "✅ Script complete. Jenkins is running on Port 8080 (Proxied through Nginx on Port 80)."