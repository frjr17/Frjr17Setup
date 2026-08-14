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
run sudo ln -sfn /var/lib/snapd/snap /snap   # -f: plain ln fails on every re-run
run sudo systemctl enable --now snapd.socket
run sudo systemctl restart snapd.socket snapd.seeded.service
run sudo snap wait system seed.loaded

# ─────────────────────────────────────────────
# Installing Multimedia codecs and drivers
# ─────────────────────────────────────────────

# Needs the RPM Fusion repos from gnomeSettings.sh — libavcodec-freeworld lives there.
step "Installing multimedia codecs and drivers"
run sudo dnf upgrade --refresh -y
run sudo dnf install -y intel-media-driver libva-utils libavcodec-freeworld

# ─────────────────────────────────────────────
# Removing preinstalled apps we don't use
# ─────────────────────────────────────────────

step "Removing Firefox"
if rpm -q firefox >/dev/null 2>&1; then
  run sudo dnf remove -y firefox firefox-langpacks
  say "removed Firefox; Brave is the browser on this machine"
else
  cached "Firefox is not installed"
fi

# Nothing else on the system depends on these three, so they come out cleanly.
# They are also dropped from the System app-folder list in gnomeSettings.sh —
# keep the two in sync if you change this set.
step "Removing unused GNOME default apps"
unwanted=()
for p in gnome-tour yelp gnome-weather; do
  rpm -q "$p" >/dev/null 2>&1 && unwanted+=("$p")
done
if (( ${#unwanted[@]} )); then
  run sudo dnf remove -y "${unwanted[@]}"
  say "removed: ${unwanted[*]}"
else
  cached "tour, help and weather are already gone"
fi

# ─────────────────────────────────────────────
# Installing apps (dnf)
# ─────────────────────────────────────────────

step "Installing LibreOffice"
run sudo dnf install -y libreoffice

step "Installing Thunderbird"
run sudo dnf install -y thunderbird

# Third-party direct downloads: their URLs go stale without notice, so a dead link
# warns instead of aborting the whole provision. Downloads land in scratch space,
# not the repo — `wget` with no -O left *.rpm.1 copies here and installed the stale one.
step "Installing Muse Sounds Manager"
muse_rpm="$BK_SCRATCH/Muse_Sounds_Manager_x64.rpm"
if run wget -q -O "$muse_rpm" https://muse-cdn.com/Muse_Sounds_Manager_x64.rpm; then
  run sudo dnf install -y "$muse_rpm" || warn "Muse Sounds Manager failed to install"
else
  warn "could not download Muse Sounds Manager — skipping"
fi

step "Installing Brave"
if command -v brave-browser >/dev/null 2>&1; then
  cached "brave-browser already installed"
else
  run bash -c 'curl -fsS https://dl.brave.com/install.sh | sh'
fi

step "Setting Brave's default fonts to Noto"
# The math family is not part of Fedora's default Noto set.
run sudo dnf install -y google-noto-sans-vf-fonts google-noto-serif-vf-fonts \
                       google-noto-sans-mono-vf-fonts google-noto-sans-math-fonts
# Warns and skips if Brave is open; the profile is merged, never replaced.
run "$SCRIPT_DIR/braveFonts.sh" "$HOME/.config/BraveSoftware/Brave-Browser/Default" ||
  warn "could not set Brave's fonts — close Brave and re-run ./braveFonts.sh"

step "Installing Visual Studio Code"
run sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
printf '[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n' | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
run sudo dnf check-update || true   # exits 100 when updates are available
run sudo dnf install -y code

step "Installing Docker Desktop"
dd_rpm="$BK_SCRATCH/docker-desktop.rpm"
if run wget -q -O "$dd_rpm" https://desktop.docker.com/linux/main/amd64/docker-desktop-x86_64.rpm; then
  run sudo dnf install -y "$dd_rpm" || warn "Docker Desktop failed to install"
else
  warn "could not download Docker Desktop — skipping"
fi

# ─────────────────────────────────────────────
# Installing apps (flatpak)
# ─────────────────────────────────────────────

step "Installing Telegram"
run flatpak install flathub org.telegram.desktop -y

step "Installing Muse Score"
run flatpak install flathub org.musescore.MuseScore -y

# Flatpak rather than RPM Fusion's `discord`: Discord refuses to start on an
# outdated client, and the Flathub build tracks upstream more closely than the
# RPM does. Swap to `dnf install -y discord` if you'd rather it be an rpm.
step "Installing Discord"
run flatpak install flathub com.discordapp.Discord -y

# ─────────────────────────────────────────────
# Installing apps (snap)
# ─────────────────────────────────────────────

step "Installing Spotify"
if snap list spotify >/dev/null 2>&1; then
  cached "spotify already installed"
else
  run sudo snap install spotify
fi

step "Exporting desktop configuration"
say "restart your GNOME session, or run: gnome-shell --replace (on X11)"
