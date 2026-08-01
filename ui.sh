#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"

# ─────────────────────────────────────────────
# Update system
# ─────────────────────────────────────────────
step "Updating system packages"
run sudo dnf update -y

# Entering temporary directory for all operations
cd /tmp

step "Installing the WhiteSur theme"
rm -rf WhiteSurInstaller   # rerun-safe: clone aborts under set -e if the dir exists
run git clone https://github.com/frjr17/WhiteSurInstaller.git
cd ./WhiteSurInstaller

chmod +x ./*.sh
run ./install.sh

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
)

for ext in "${extensions[@]}"; do
  say "installing $ext"
  run gnome-extensions-cli install "$ext" || warn "failed to install: $ext"
done

# Installing Compiz Alike Magic Lamp Effect
step "Installing Compiz Alike Magic Lamp Effect"
cd /tmp   # WhiteSur install above left us inside its clone dir
rm -rf compiz-alike-magic-lamp-effect

run git clone https://github.com/hermes83/compiz-alike-magic-lamp-effect.git
cd compiz-alike-magic-lamp-effect

if run bash install.sh; then
  say "restart GNOME Shell for the effect to take hold"
else
  warn "install failed, continuing with the rest of the script"
fi

# Installing Hide Top Bar extension
step "Installing the Hide Top Bar extension"
cd /tmp
rm -rf hidetopbar

run git clone https://gitlab.gnome.org/tuxor1337/hidetopbar.git
cd hidetopbar

run make
run gnome-extensions-cli install ./hidetopbar.zip

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
