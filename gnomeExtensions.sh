#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"

# ─────────────────────────────────────────────
# Update system
# ─────────────────────────────────────────────
step "Updating system packages"
run sudo dnf update -y

# ─────────────────────────────────────────────
# Install pipx and gnome-extensions-cli
# ─────────────────────────────────────────────

step "Ensuring pipx is available"
if command -v pipx &> /dev/null; then
    cached "pipx already installed"
else
    run sudo dnf install -y pipx python3-pip
fi

step "Installing gnome-extensions-cli"
run pipx ensurepath
# Reload shell environment to make pipx available immediately
export PATH="$HOME/.local/bin:$PATH"
run pipx install gnome-extensions-cli --system-site-packages

# ─────────────────────────────────────────────
# Install Extension Manager (GUI)
# ─────────────────────────────────────────────

step "Installing the GNOME Extension Manager GUI"
run sudo flatpak install -y flathub com.mattjakeman.ExtensionManager

# ─────────────────────────────────────────────
# Install GNOME Extensions via CLI
# ─────────────────────────────────────────────

step "Installing GNOME Shell extensions"
extensions=(
  user-theme@gnome-shell-extensions.gcampax.github.com
  blur-my-shell@aunetx
  dash-to-dock@micxgx.gmail.com
  logomenu@aryan_k
  Hide_Activities@shay.shayel.org
  just-perfection-desktop@just-perfection
  moveclock@kuvaus.org
  compiz-alike-magic-lamp-effect@hermes83.github.com
  hidetopbar@mathieu.bidon.ca
)

for ext in "${extensions[@]}"; do
  say "installing $ext"
  run gnome-extensions-cli install "$ext" || warn "failed to install: $ext"
done
