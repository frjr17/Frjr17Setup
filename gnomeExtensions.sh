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
# pipx's exit code for an already-installed package varies between versions, so
# check for the binary rather than relying on it.
if command -v gnome-extensions-cli >/dev/null 2>&1; then
    cached "gnome-extensions-cli already installed"
else
    run pipx install gnome-extensions-cli --system-site-packages
fi

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
  # --filesystem extracts the zip directly instead of going through the dbus
  # backend, which pops a Yes/No dialog in the Shell and blocks forever with
  # nobody there to click it.
  run gnome-extensions-cli --filesystem install "$ext" || warn "failed to install: $ext"
  run gnome-extensions enable "$ext" || warn "failed to enable: $ext"
done

# ─────────────────────────────────────────────
# Apply extension settings
# ─────────────────────────────────────────────

step "Applying extension settings"
# Only the keys that differ from each extension's schema default. Dash to Dock,
# Just Perfection, Hide Activities and Magic Lamp run stock.
settings=(
  "user-theme/name 'WhiteSur-Dark-purple'"      # shell theme; whitesurTheme.sh only sets GTK
  "Logo-menu/menu-button-icon-image 1"          # Fedora logo, not start-here
  "Logo-menu/menu-button-icon-size 20"
  "blur-my-shell/panel/sigma 0"                 # sigma 0 = no blur, only the dimming
  "blur-my-shell/panel/brightness 0.41"
  "blur-my-shell/panel/static-blur false"
  "blur-my-shell/dash-to-dock/sigma 0"
  "blur-my-shell/dash-to-dock/static-blur false"
  "hidetopbar/mouse-sensitive true"             # reveal the top bar on hover
  "moveclock/clock-before-statusmenu true"      # clock next to the status menu
)

for s in "${settings[@]}"; do
  key=${s%% *} value=${s#* }
  say "$key = $value"
  run dconf write "/org/gnome/shell/extensions/$key" "$value"
done
