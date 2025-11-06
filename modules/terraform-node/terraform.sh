#!/usr/bin/env bash
# Terraform/Jenkins build-node bootstrap (Ubuntu 24.04 Noble) — Nov 2025

set -euo pipefail

# ----------------------------- Versions -----------------------------
TF_VERSION="1.10.3"
KUBECTL_VERSION="1.32.0"
TFLINT_VERSION="0.55.0"
TFSEC_VERSION="1.28.6"
CHECKOV_VERSION="3.2.262"
YQ_VERSION="4.44.3"

log() { printf "\n\033[1;36m[BUILD-NODE]\033[0m %s\n" "$*"; }

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Please run as root (sudo)."; exit 1
  fi
}

arch_triplet() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) echo "amd64" ;;
  esac
}

install_base_ubuntu() {
  log "Updating apt and installing base packages (Ubuntu 24.04)..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  # NOTE: apt-transport-https is built-in on modern apt; no need to install.
  apt-get install -y --no-install-recommends \
    ca-certificates curl unzip tar git jq gpg gpg-agent lsb-release \
    python3 python3-venv pipx bash-completion fontconfig openjdk-17-jre make
  update-ca-certificates
  # Ensure pipx path
  command -v pipx >/dev/null 2>&1 || python3 -m pip install -U pipx --break-system-packages
  pipx ensurepath || true
}

ensure_jenkins_user() {
  log "Creating 'jenkins' user and agent dir (if needed)..."
  id -u jenkins >/dev/null 2>&1 || useradd -m -s /bin/bash jenkins
  mkdir -p /home/jenkins/agent
  chown -R jenkins:jenkins /home/jenkins
}

install_docker() {
  log "Installing Docker (get.docker.com)..."
  if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sh
  fi
  usermod -aG docker jenkins || true
  systemctl enable --now docker || true
  docker --version || true
}

harden_ssh() {
  log "Hardening SSH (disable password auth, ensure host keys)..."
  if [ -f /etc/ssh/sshd_config ]; then
    sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
    ssh-keygen -A >/dev/null 2>&1 || true
    systemctl restart ssh || true
  fi
}

install_awscli() {
  log "Installing AWS CLI v2..."
  local arch pkg
  arch="$(arch_triplet)"
  if [ "$arch" = "arm64" ]; then
    pkg="awscli-exe-linux-aarch64.zip"
  else
    pkg="awscli-exe-linux-x86_64.zip"
  fi
  curl -fsSL "https://awscli.amazonaws.com/${pkg}" -o /tmp/awscliv2.zip
  unzip -q -o /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install --update
  rm -rf /tmp/aws /tmp/awscliv2.zip
  aws --version || true
}

install_terraform() {
  log "Installing Terraform ${TF_VERSION} (HashiCorp APT with fallback)..."
  set +e
  # HashiCorp repo (preferred)
  curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/hashicorp.list
  apt-get update -y
  if apt-get install -y "terraform=${TF_VERSION}*"; then
    set -e; terraform -version; return
  fi
  log "APT install failed; falling back to static binary..."
  # Fallback to static binary
  curl -fsSLo /tmp/terraform.zip "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip"
  unzip -q -o /tmp/terraform.zip -d /usr/local/bin
  rm -f /tmp/terraform.zip
  set -e
  terraform -version
}

install_kubectl() {
  log "Installing kubectl ${KUBECTL_VERSION}..."
  local arch
  arch="$(arch_triplet)"
  curl -fsSLo /usr/local/bin/kubectl \
    "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${arch}/kubectl"
  chmod +x /usr/local/bin/kubectl
  kubectl version --client || true
}

install_tflint() {
  log "Installing tflint ${TFLINT_VERSION}..."
  curl -fsSLo /tmp/tflint.zip \
    "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_amd64.zip"
  unzip -q -o /tmp/tflint.zip -d /usr/local/bin
  rm -f /tmp/tflint.zip
  tflint --version || true
}

install_tfsec() {
  log "Installing tfsec ${TFSEC_VERSION}..."
  curl -fsSLo /usr/local/bin/tfsec \
    "https://github.com/aquasecurity/tfsec/releases/download/v${TFSEC_VERSION}/tfsec-linux-amd64"
  chmod +x /usr/local/bin/tfsec
  tfsec --version || true
}

install_checkov() {
  log "Installing checkov ${CHECKOV_VERSION} with pipx (avoids PEP 668 issues)..."
  # pipx puts shims in /usr/local/bin for root
  pipx install "checkov==${CHECKOV_VERSION}" --force || true
  /usr/local/bin/checkov -v || true
}

install_yq() {
  log "Installing yq ${YQ_VERSION}..."
  local arch
  arch="$(arch_triplet)"
  curl -fsSLo /usr/local/bin/yq \
    "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${arch}"
  chmod +x /usr/local/bin/yq
  yq --version || true
}

readiness_report() {
  log "Tool readiness report"
  echo "-----------------------------------------------------------"
  aws --version || true
  terraform -version | head -n1 || true
  kubectl version --client=true || true
  tflint --version || true
  tfsec --version || true
  /usr/local/bin/checkov -v || true
  yq --version || true
  echo "-----------------------------------------------------------"
  log "STS identity check (optional)..."
  aws sts get-caller-identity || echo "No AWS credentials detected yet."
  log "✅ Build node ready for Terraform CI/CD pipelines."
}

main() {
  require_root
  install_base_ubuntu
  ensure_jenkins_user
  install_docker
  harden_ssh

  install_awscli
  install_terraform
  install_kubectl
  install_tflint
  install_tfsec
  install_checkov
  install_yq

  readiness_report
}

main "$@"
