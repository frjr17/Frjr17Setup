#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"

# ─────────────────────────────────────────────
# Update system
# ─────────────────────────────────────────────
step "Updating system packages"
run sudo dnf update -y

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly REPO_DIR
WORK_DIR="$(mktemp -d)"
trap 'rm -rf -- "${WORK_DIR}"' EXIT

git clone --depth=1 https://github.com/frjr17/WhiteSurCursors.git "${WORK_DIR}/WhiteSurCursors"
(cd "${WORK_DIR}/WhiteSurCursors" && ./install.sh)

git clone --depth=1 https://github.com/frjr17/WhiteSurIconTheme.git "${WORK_DIR}/WhiteSurIconTheme"
(cd "${WORK_DIR}/WhiteSurIconTheme" && ./install.sh)

git clone --depth=1 https://github.com/frjr17/WhiteSurGtkTheme.git "${WORK_DIR}/WhiteSurGtkTheme"
(
  cd "${WORK_DIR}/WhiteSurGtkTheme"
  ./install.sh --fullblack -c dark -t purple -l      
  flatpak override --user --filesystem=xdg-config/gtk-4.0:ro --filesystem=xdg-config/gtk-3.0:ro
  gsettings set org.gnome.desktop.interface gtk-theme "WhiteSur-Dark-purple"
)

screen_resolution="$("${REPO_DIR}/screen-res.sh")"
echo "Your screen resolution variant is ${screen_resolution}"

git clone --depth=1 https://github.com/frjr17/WhiteSurWallpapers.git "${WORK_DIR}/WhiteSurWallpapers"
(
  cd "${WORK_DIR}/WhiteSurWallpapers"
  ./install-gnome-backgrounds.sh -t whitesur -s "${screen_resolution}"
)