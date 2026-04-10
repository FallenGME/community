#!/usr/bin/env bash
# =============================================================================
# setup.sh — one-time VPS preparation for Discourse + community forum
#
# Run as root on a fresh Ubuntu 22.04 LTS instance:
#   curl -fsSL https://raw.githubusercontent.com/ChrisTitusTech/community/main/scripts/setup.sh | bash
#
# What this does:
#   1. Updates system packages
#   2. Installs Docker (official repo)
#   3. Configures UFW firewall (22, 80, 443 only)
#   4. Creates a system swap file (2 GB, as required by discourse_docker)
#   5. Clones discourse_docker to /var/discourse
#   6. Sets up a /var/discourse/containers directory ready for app.yml
# =============================================================================

set -euo pipefail

DISCOURSE_DIR="/var/discourse"
SWAP_SIZE_GB=2

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Root check ────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root. Use: sudo bash setup.sh"
fi

info "============================================"
info " ChrisTitusTech Community — VPS Setup"
info "============================================"

# ── 1. System update ──────────────────────────────────────────────────────────
info "Updating system packages..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq

# Install utilities used by Discourse bootstrap
apt-get install -y -qq \
  git \
  curl \
  ca-certificates \
  gnupg \
  lsb-release \
  ufw \
  fail2ban

# ── 2. Install Docker ─────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  info "Installing Docker..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin
  systemctl enable --now docker
  info "Docker $(docker --version) installed."
else
  info "Docker already installed: $(docker --version)"
fi

# ── 3. Firewall ───────────────────────────────────────────────────────────────
info "Configuring UFW firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp  comment "SSH"
ufw allow 80/tcp  comment "HTTP (Discourse + Let's Encrypt)"
ufw allow 443/tcp comment "HTTPS (Discourse)"
ufw --force enable
info "UFW status:"
ufw status verbose

# ── 4. fail2ban (basic SSH brute-force protection) ────────────────────────────
info "Enabling fail2ban..."
systemctl enable --now fail2ban

# ── 5. Swap file ──────────────────────────────────────────────────────────────
if swapon --show | grep -q /swapfile; then
  info "Swap already exists — skipping."
else
  info "Creating ${SWAP_SIZE_GB} GB swap file at /swapfile..."
  fallocate -l "${SWAP_SIZE_GB}G" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  # Persist across reboots
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  # Reduce swappiness for a database-heavy workload
  sysctl -w vm.swappiness=10
  grep -q 'vm.swappiness' /etc/sysctl.conf \
    || echo 'vm.swappiness=10' >> /etc/sysctl.conf
  info "Swap configured."
fi

# ── 6. Clone discourse_docker ─────────────────────────────────────────────────
if [[ -d "$DISCOURSE_DIR" ]]; then
  info "discourse_docker already cloned at $DISCOURSE_DIR — pulling latest..."
  git -C "$DISCOURSE_DIR" pull --ff-only
else
  info "Cloning discourse_docker to $DISCOURSE_DIR..."
  git clone https://github.com/discourse/discourse_docker.git "$DISCOURSE_DIR"
fi

mkdir -p "$DISCOURSE_DIR/containers"
chmod 700 "$DISCOURSE_DIR/containers"

# ── 7. Kernel / system tuning ─────────────────────────────────────────────────
info "Applying kernel tweaks for Discourse..."
# Increase file descriptor limits
cat >> /etc/security/limits.conf <<'EOF'
*  soft  nofile  65535
*  hard  nofile  65535
EOF

# Increase inotify limits (needed for many containers)
echo 'fs.inotify.max_user_watches=524288' >> /etc/sysctl.conf
sysctl -p /etc/sysctl.conf 2>/dev/null || true

# ── Done ──────────────────────────────────────────────────────────────────────
info "============================================"
info " Setup complete!"
info "============================================"
echo ""
echo "Next steps:"
echo "  1. Copy your app.yml to ${DISCOURSE_DIR}/containers/app.yml"
echo "     Fill in all REPLACE_WITH_* placeholders."
echo ""
echo "  2. Bootstrap Discourse:"
echo "     cd ${DISCOURSE_DIR}"
echo "     ./launcher bootstrap app"
echo "     ./launcher start app"
echo ""
echo "  3. Publish the plugin repo (see README.md) before bootstrapping"
echo "     so the after_code hook can clone it."
