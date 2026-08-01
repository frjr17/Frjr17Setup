#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"

# ─────────────────────────────────────────────
# Vim
# ─────────────────────────────────────────────
step "Installing Vim"
run sudo dnf install -y vim

# ─────────────────────────────────────────────
# NVM, Node.js & npm
# ─────────────────────────────────────────────
step "Installing NVM"
run bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash'

step "Installing Node.js (LTS)"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
run nvm install --lts

# ─────────────────────────────────────────────
# npm Configuration
# ─────────────────────────────────────────────
# Install repository .npmrc into the user's home so npm uses consistent defaults
step "Installing npm config"
if [ -f "$SCRIPT_DIR/.npmrc" ]; then
    cp "$SCRIPT_DIR/.npmrc" "$HOME/.npmrc"
    say ".npmrc copied to $HOME/.npmrc"
else
    cached ".npmrc not found in repo; skipping npm config install"
fi

# ─────────────────────────────────────────────
# Docker
# ─────────────────────────────────────────────
step "Removing distro Docker packages"
run sudo dnf remove -y docker \
                      docker-client \
                      docker-client-latest \
                      docker-common \
                      docker-latest \
                      docker-latest-logrotate \
                      docker-logrotate \
                      docker-selinux \
                      docker-engine-selinux \
                      docker-engine

step "Installing Docker CE"
run sudo dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
run sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

step "Enabling Docker service"
run sudo systemctl enable --now docker
run sudo usermod -aG docker "$USER"

step "Exporting development environment"
say "restart your computer to apply the docker group change"
