#!/usr/bin/env bash
set -euo pipefail

########################
# Config (edit as needed)
########################
DOMAIN="${DOMAIN:-jenkins.fusisoft.com}"
EMAIL="${EMAIL:-fusisoft@gmail.com}"

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

echo "==> Using DOMAIN=${DOMAIN}"
echo "==> Using EMAIL=${EMAIL}"

########################
# 0) Basic sanity
########################
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo)."; exit 1
fi

# Keep track of invoking user for docker group
INVOCATOR="${SUDO_USER:-${USER}}"

########################
# 1) System update & base tools
########################
echo "==> Updating system packages..."
apt-get update -y
apt-get upgrade -y
apt-get install -y \
  ca-certificates curl gnupg lsb-release \
  apt-transport-https software-properties-common \
  unzip git ufw

########################
# 2) Install Docker Engine
########################
echo "==> Installing Docker..."
apt-get remove -y docker docker-engine docker.io containerd runc || true

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

ARCH="$(dpkg --print-architecture)"
CODENAME="$(lsb_release -cs)"
echo \
  "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io

systemctl enable --now docker

# Docker group for both the invoking user and Jenkins (added later)
usermod -aG docker "${INVOCATOR}" || true

########################
# 3) Java 17 + Maven
########################
echo "==> Installing OpenJDK 17 and Maven..."
apt-get install -y openjdk-17-jdk maven
update-alternatives --set java /usr/lib/jvm/java-1.17.0-openjdk-amd64/bin/java || true || true

########################
# 4) AWS CLI v2, kubectl, Helm (for builds/deploys)
########################
echo "==> Installing AWS CLI v2..."
tmpdir="$(mktemp -d)"
pushd "$tmpdir" >/dev/null
curl -fsSLo awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
unzip -q awscliv2.zip
./aws/install --update
popd >/dev/null
rm -rf "$tmpdir"

echo "==> Installing kubectl..."
curl -fsSLo /usr/local/bin/kubectl \
  "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl
kubectl version --client=true --short || true

echo "==> Installing Helm..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version || true

########################
# 5) Install Jenkins LTS
########################
echo "==> Installing Jenkins LTS..."
curl -fsSL https://pkg.jenkins.io/debian/jenkins.io-2023.key \
  | tee /usr/share/keyrings/jenkins-keyring.asc >/dev/null

echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian binary/" \
  > /etc/apt/sources.list.d/jenkins.list

apt-get update -y
apt-get install -y jenkins

# Ensure Jenkins uses Java 17
sed -i 's|^#*JAVA_HOME=.*|JAVA_HOME=/usr/lib/jvm/java-1.17.0-openjdk-amd64|' /etc/default/jenkins || true

# Allow Jenkins to run Docker
usermod -aG docker jenkins || true

systemctl daemon-reload
systemctl enable --now jenkins

########################
# 6) Nginx + Certbot reverse proxy for Jenkins
########################
echo "==> Installing Nginx + Certbot..."
apt-get install -y nginx certbot python3-certbot-nginx

# UFW basic rules
echo "==> Configuring UFW..."
ufw allow OpenSSH || true
ufw allow 'Nginx Full' || true
# Enable UFW if not already enabled
ufw --force enable || true

# Hardened Nginx site with WebSocket + headers
echo "==> Writing Nginx server block for ${DOMAIN}..."
cat >/etc/nginx/sites-available/jenkins.conf <<EOL
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    # Redirect to HTTPS handled by certbot --redirect (will update server blocks)
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_request_buffering off;

        # WebSocket support for Jenkins
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Large timeouts for long-running operations
    client_max_body_size 0;
    proxy_read_timeout 600s;
    proxy_connect_timeout 600s;
    proxy_send_timeout 600s;
}
EOL

ln -sfn /etc/nginx/sites-available/jenkins.conf /etc/nginx/sites-enabled/jenkins.conf
rm -f /etc/nginx/sites-enabled/default || true
nginx -t
systemctl reload nginx

echo "==> Requesting Let's Encrypt certificate for ${DOMAIN}..."
# This will also add the HTTPS server block and enable --redirect automatically
certbot --nginx --non-interactive --agree-tos -m "${EMAIL}" -d "${DOMAIN}" --redirect

# Ensure systemd timer is active (default on ubuntu certbot package)
systemctl enable --now certbot.timer

########################
# 7) Jenkins URL + Info
########################
JENKINS_URL="https://${DOMAIN}"
echo "JENKINS_ARGS=\"--prefix=/\"" >> /etc/default/jenkins || true
systemctl restart jenkins

echo "==> Jenkins initial admin password:"
if [[ -f /var/lib/jenkins/secrets/initialAdminPassword ]]; then
  cat /var/lib/jenkins/secrets/initialAdminPassword
else
  echo "(Not yet generated; wait a few seconds and check /var/lib/jenkins/secrets/initialAdminPassword)"
fi

echo "✅ Jenkins should be available at: ${JENKINS_URL}"
echo "ℹ️  You must log out/in (or reboot) for Docker group membership to take effect for ${INVOCATOR} and jenkins users."
