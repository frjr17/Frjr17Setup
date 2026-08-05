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
# Update system
# ─────────────────────────────────────────────
step "Installing snap"
run sudo dnf install snapd -y
run sudo ln -s /var/lib/snapd/snap /snap
run sudo systemctl enable --now snapd.socket
run sudo systemctl restart snapd.socket snapd.seeded.service
run sudo snap wait system seed.loaded

# ─────────────────────────────────────────────
# Installing Multimedia codecs and drivers
# ─────────────────────────────────────────────

step "Installing multimedia codecs and drivers"
run sudo dnf upgrade --refresh
run sudo dnf install -y intel-media-driver libva-utils libavcodec-freeworld

# ─────────────────────────────────────────────
# Installing apps (dnf)
# ─────────────────────────────────────────────

step "Installing LibreOffice"
run sudo dnf install -y libreoffice

step "Installing Thunderbird"
run sudo dnf install -y thunderbird

step "Installing Muse Sounds Manager"
run wget https://muse-cdn.com/Muse_Sounds_Manager_x64.rpm
run sudo dnf install Muse_Sounds_Manager_x64.rpm

step "Installing Brave"
run bash -c 'curl -fsS https://dl.brave.com/install.sh | sh'

step "Installing Visual Studio Code"
run sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
printf '[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n' | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
run sudo dnf check-update || true   # exits 100 when updates are available
run sudo dnf install -y code

step "Installing Docker Desktop"
run wget https://desktop.docker.com/linux/main/amd64/docker-desktop-x86_64.rpm -O docker-desktop.rpm
run sudo dnf install -y ./docker-desktop.rpm

# ─────────────────────────────────────────────
# Installing apps (flatpak)
# ─────────────────────────────────────────────

step "Installing Telegram"
run flatpak install flathub org.telegram.desktop -y

step "Installing Muse Score"
run flatpak install flathub org.musescore.MuseScore -y

# ─────────────────────────────────────────────
# Installing apps (snap)
# ─────────────────────────────────────────────

step "Installing Spotify"
run sudo snap install spotify

step "Exporting desktop configuration"
say "restart your GNOME session, or run: gnome-shell --replace (on X11)"
