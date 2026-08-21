#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"

THEME_NAME="WhiteSur-Dark-purple"
ICON_THEME_NAME="WhiteSur-dark"
CURSOR_THEME_NAME="WhiteSur-cursors"

# ─────────────────────────────────────────────
# Update system
# ─────────────────────────────────────────────
step "Updating system packages"
run sudo dnf update -y

step "Installing GNOME Tweaks"
run sudo dnf install -y gnome-tweaks

# Scratch space comes from log.sh: a local `trap ... EXIT` here would replace
# log.sh's trap, and the run would lose its DONE/FINISHED and ERROR output.
WORK_DIR="$BK_SCRATCH"

# ─────────────────────────────────────────────
# Cursors and icons
# ─────────────────────────────────────────────

step "Installing WhiteSur cursors"
run git clone --depth=1 https://github.com/frjr17/WhiteSurCursors.git "$WORK_DIR/WhiteSurCursors"
run bash -c 'cd "$1" && ./install.sh' _ "$WORK_DIR/WhiteSurCursors"

step "Installing WhiteSur icon theme"
run git clone --depth=1 https://github.com/frjr17/WhiteSurIconTheme.git "$WORK_DIR/WhiteSurIconTheme"
run bash -c 'cd "$1" && ./install.sh' _ "$WORK_DIR/WhiteSurIconTheme"

# ─────────────────────────────────────────────
# GTK theme
# ─────────────────────────────────────────────

step "Installing the WhiteSur GTK theme"
run git clone --depth=1 https://github.com/frjr17/WhiteSurGtkTheme.git "$WORK_DIR/WhiteSurGtkTheme"
run bash -c 'cd "$1" && ./install.sh --fullblack -c dark -t purple -l' _ "$WORK_DIR/WhiteSurGtkTheme"

step "Applying GDM and Flatpak tweaks"
run sudo bash -c 'cd "$1" && ./tweaks.sh -g -p 60' _ "$WORK_DIR/WhiteSurGtkTheme"
run flatpak override --user --filesystem=xdg-config/gtk-4.0:ro --filesystem=xdg-config/gtk-3.0:ro

step "Selecting the WhiteSur theme in GNOME"
if [[ -z ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
  warn "no session bus — cannot select the theme; run this from a desktop session"
else
  run gsettings set org.gnome.desktop.interface gtk-theme "$THEME_NAME"
  run gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME_NAME"
  run gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR_THEME_NAME"
  # Not exposed in Tweaks (that's the Settings app's Appearance/Date & Time
  # panels), but they're part of the same look-and-feel this script sets up.
  run gsettings set org.gnome.desktop.interface color-scheme prefer-dark
  run gsettings set org.gnome.desktop.interface clock-format 12h
fi
