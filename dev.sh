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
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    cached "nvm already installed at $NVM_DIR"
else
    run bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash'
fi

step "Installing Node.js (LTS)"
# Without the guard, a missing nvm.sh means the next line dies with a bare
# "nvm: command not found" and no indication that the install step is at fault.
if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    warn "nvm.sh missing after install — skipping Node"
else
    # shellcheck disable=SC1091
    \. "$NVM_DIR/nvm.sh"
    run nvm install --lts
fi

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
# addrepo fails outright when the repo file is already there.
if [ -f /etc/yum.repos.d/docker-ce.repo ]; then
    say "docker-ce repo already configured"
else
    run sudo dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
fi
run sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

step "Enabling Docker service"
run sudo systemctl enable --now docker
if id -nG "$USER" | grep -qw docker; then
    say "$USER is already in the docker group"
else
    run sudo usermod -aG docker "$USER"
    say "restart your computer to apply the docker group change"
fi

step "Exporting development environment"
say "docker: $(docker --version 2>/dev/null || echo 'not on PATH yet')"
