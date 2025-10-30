#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

DOMAIN="jenkins.fusisoft.com"
ADMIN_EMAIL="fusisoft@gmail.com"

echo "[1/7] Base packages & Java"
apt-get update -y
apt-get install -y curl gnupg ca-certificates lsb-release openjdk-17-jdk ufw dnsutils

echo "[2/7] Jenkins repo & install"
if [ ! -f /usr/share/keyrings/jenkins-keyring.asc ]; then
  curl -fsSL https://pkg.jenkins.io/debian/jenkins.io-2023.key | tee /usr/share/keyrings/jenkins-keyring.asc >/dev/null
fi
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  | tee /etc/apt/sources.list.d/jenkins.list >/dev/null

apt-get update -y
apt-get install -y jenkins
systemctl enable --now jenkins

echo "[3/7] Nginx + Certbot"
apt-get install -y nginx certbot python3-certbot-nginx
rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/ln || true

echo "[4/7] Nginx HTTP reverse proxy (no HTTPS yet)"
tee /etc/nginx/sites-available/jenkins.conf >/dev/null <<'EOL'
server {
    listen 80;
    listen [::]:80;
    server_name jenkins.fusisoft.com;

    # Forward all traffic to Jenkins (local)
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

echo "[5/7] Firewall (external 80/443 allowed; block direct 8080)"
ufw allow 80/tcp || true
ufw allow 443/tcp || true
ufw deny  8080/tcp || true
ufw reload || true

echo "[6/7] Install a background job that waits for DNS, then enables HTTPS"
cat >/usr/local/bin/issue-cert-when-dns-ready.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

DOMAIN="jenkins.fusisoft.com"
ADMIN_EMAIL="fusisoft@gmail.com"
MAX_TRIES=240          # ~2 hours at 30s intervals
SLEEP_SECS=30

log() { echo "[issue-cert] $*"; }

# Get instance public IP (IMDSv1/2 compatible without session)
PUBIP="$(curl -fsS http://169.254.169.254/latest/meta-data/public-ipv4 || true)"
if [ -z "$PUBIP" ]; then
  log "No instance public IP (likely no EIP attached). Exiting."
  exit 0
fi

log "Instance public IP: $PUBIP"
log "Waiting for DNS A($DOMAIN) to equal ${PUBIP} ..."

i=0
while :; do
  DNSIP="$(dig +short ${DOMAIN} A | head -n1 || true)"
  if [ -n "$DNSIP" ] && [ "$DNSIP" = "$PUBIP" ]; then
    log "DNS matches (${DNSIP}). Proceeding to obtain certificate."
    break
  fi
  i=$((i+1))
  if [ "$i" -ge "$MAX_TRIES" ]; then
    log "Timed out waiting for DNS; leaving site on HTTP."
    exit 0
  fi
  sleep "$SLEEP_SECS"
done

# Make sure Jenkins is up (first boot can take some time)
for n in {1..60}; do
  if curl -fsSI http://127.0.0.1:8080/login >/dev/null; then
    break
  fi
  sleep 2
done

# Obtain cert and enable HTTPS + redirect
if certbot --nginx \
    -d "$DOMAIN" -m "$ADMIN_EMAIL" \
    --agree-tos --no-eff-email --non-interactive --redirect; then
  log "Certificate obtained and Nginx updated."
  systemctl reload nginx || true
  systemctl enable --now certbot.timer || true
else
  log "Certbot failed; leaving site on HTTP."
fi
SCRIPT
chmod +x /usr/local/bin/issue-cert-when-dns-ready.sh

# systemd service + timer to poll until DNS is ready, then run Certbot
cat >/etc/systemd/system/issue-cert.service <<'UNIT'
[Unit]
Description=Obtain Let's Encrypt cert when DNS points here
Wants=network-online.target
After=network-online.target nginx.service jenkins.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/issue-cert-when-dns-ready.sh
UNIT

cat >/etc/systemd/system/issue-cert.timer <<'TIMER'
[Unit]
Description=Poll DNS and enable HTTPS when ready

[Timer]
OnBootSec=30s
OnUnitActiveSec=5m
Persistent=true
Unit=issue-cert.service

[Install]
WantedBy=timers.target
TIMER

systemctl daemon-reload
systemctl enable --now issue-cert.timer

echo "[7/7] Final checks"
nginx -t
systemctl restart nginx
systemctl status nginx --no-pager | sed -n '1,12p'
systemctl status jenkins --no-pager | sed -n '1,12p'

echo "✅ Jenkins is live on HTTP now. Create/point Route53 A record for ${DOMAIN} to this instance's EIP."
echo "🕒 The server will auto-switch to HTTPS and 301-redirect once DNS resolves to this host."
