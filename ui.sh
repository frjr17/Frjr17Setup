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
# Installing RPM Fusion
# ─────────────────────────────────────────────

step "Enabling the RPM Fusion repositories"
# -y is required now: dnf's confirmation prompt is invisible through the log pipe.
run sudo dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

# ─────────────────────────────────────────────
# Installing Multimedia codecs and drivers
# ─────────────────────────────────────────────

step "Installing multimedia codecs and drivers"
run sudo dnf upgrade --refresh
run sudo dnf install -y intel-media-driver libva-utils libavcodec-freeworld

# ─────────────────────────────────────────────
# Installing apps
# ─────────────────────────────────────────────

step "Installing Snapd"
run sudo dnf install snapd -y
sudo ln -s /var/lib/snapd/snap /snap || say "/snap symlink already present"

step "Installing LibreOffice"
run sudo dnf install -y libreoffice

step "Installing Brave"
run bash -c 'curl -fsS https://dl.brave.com/install.sh | sh'

step "Installing Spotify"
run sudo snap install spotify

step "Installing Visual Studio Code"
run sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
printf '[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n' | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
run sudo dnf check-update || true   # exits 100 when updates are available
run sudo dnf install -y code

step "Installing the Google Drive File Stream driver"
run sudo dnf copr enable fluhus/gnome-googledrive
run sudo dnf update --refresh

step "Installing Telegram"
run sudo snap install telegram-desktop

step "Installing Docker Desktop"
run wget https://desktop.docker.com/linux/main/amd64/docker-desktop-x86_64.rpm -O docker-desktop.rpm
run sudo dnf install -y ./docker-desktop.rpm

step "Installing MuseScore"
run wget https://cdn.jsdelivr.net/musescore/v4.6.5/MuseScore-Studio-4.6.5.253511702-x86_64.AppImage
chmod +x MuseScore-Studio-4.6.5.253511702-x86_64.AppImage
run ./MuseScore-Studio-4.6.5.253511702-x86_64.AppImage install

step "Installing Linux Dynamic Wallpapers"
cd /tmp
rm -rf LinuxDynamicWallpapers
run git clone https://github.com/frjr17/LinuxDynamicWallpapers.git
cd LinuxDynamicWallpapers
run sudo bash ./install.sh

step "Installing Thunderbird"
run sudo dnf install -y thunderbird

step "Exporting desktop configuration"
say "restart your GNOME session, or run: gnome-shell --replace (on X11)"
