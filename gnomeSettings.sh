#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"

# ─────────────────────────────────────────────
# Installing RPM Fusion
# ─────────────────────────────────────────────

step "Enabling the RPM Fusion repositories"
# -y is required now: dnf's confirmation prompt is invisible through the log pipe.
if rpm -q rpmfusion-free-release rpmfusion-nonfree-release >/dev/null 2>&1; then
  cached "RPM Fusion already enabled"
else
  run sudo dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
fi

# ─────────────────────────────────────────────
# Keyboard Commands
# ─────────────────────────────────────────────

step "Setting custom keyboard shortcuts"

# gsettings talks to the user session bus. Over SSH there isn't one, and every
# `gsettings set` below fails one at a time with no hint why — say it once, up front.
[[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] ||
  warn "no session bus — GNOME settings will not apply; run this from a desktop session"

# Window movement between monitors
run gsettings set org.gnome.desktop.wm.keybindings move-to-monitor-down "['<Shift><Super>Down']"
run gsettings set org.gnome.desktop.wm.keybindings move-to-monitor-left "['<Shift><Super>Left']"
run gsettings set org.gnome.desktop.wm.keybindings move-to-monitor-right "['<Shift><Super>Right']"
run gsettings set org.gnome.desktop.wm.keybindings move-to-monitor-up "['<Shift><Super>Up']"
run gsettings set org.gnome.desktop.wm.keybindings switch-applications "[]"
run gsettings set org.gnome.desktop.wm.keybindings switch-windows "['<Alt>Tab']"

# Workspace navigation
run gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-left "['<Shift><Alt>Left']"
run gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-right "['<Shift><Alt>Right']"

# Fullscreen toggle
run gsettings set org.gnome.desktop.wm.keybindings toggle-fullscreen "['F4']"

# Show applications (Activities)
run gsettings set org.gnome.shell.keybindings toggle-application-view "['<Super>a']"

# Notifications — Super+N is GNOME's default focus-active-notification, so free it
# first, otherwise the two grabs collide and the message tray never opens.
run gsettings set org.gnome.shell.keybindings focus-active-notification "[]"
run gsettings set org.gnome.shell.keybindings toggle-message-tray "['<Super>n']"

# Settings
run gsettings set org.gnome.settings-daemon.plugins.media-keys control-center "['<Super>i']"

# "Open File Explorer" shortcut (custom one)
step "Binding Super+E to the file explorer"
run gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ name 'Open File Explorer'
run gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ command 'nautilus'
run gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding '<Super>e'

# The three settings above are inert until the path is listed here — this is the
# step everyone forgets. Append instead of overwrite, so bindings added through
# GNOME Settings survive a re-run.
custom0=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/
bound=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
case $bound in
  *"$custom0"*) say "custom0 already registered" ;;
  '@as []'|'[]') run gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['$custom0']" ;;
  *)             run gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "${bound%]}, '$custom0']" ;;
esac

# ─────────────────────────────────────────────
# Dock
# ─────────────────────────────────────────────

# The dock is just GNOME's favourites list. Entries whose .desktop file isn't
# installed yet are ignored by the shell and appear on their own once the app
# lands — so this is safe to set before apps.sh and bravePwa.sh have run.
# Order here is the left-to-right order in the dock.
step "Setting the dock favourites"
run gsettings set org.gnome.shell favorite-apps "[
  'brave-browser.desktop',
  'brave-pwa-whatsapp.desktop',
  'org.telegram.desktop.desktop',
  'brave-pwa-notion.desktop',
  'brave-pwa-work-whatsapp.desktop',
  'spotify_spotify.desktop',
  'net.thunderbird.Thunderbird.desktop',
  'org.musescore.MuseScore.desktop',
  'brave-pwa-chatgpt.desktop',
  'brave-pwa-claude.desktop',
  'org.gnome.TextEditor.desktop'
]"

# ─────────────────────────────────────────────
# App grid folders
# ─────────────────────────────────────────────

step "Setting the app grid folders"

# <id> <name> <translate> <apps>. translate=true means the name is a .directory
# file GNOME localises; a literal folder name uses false.
app_folder() {
  local path="org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/$1/"
  run gsettings set "$path" name "$2"
  run gsettings set "$path" translate "$3"
  run gsettings set "$path" apps "$4"
}

# Fedora ships empty YaST and Pardus folders in this list for other distros;
# they are dropped here rather than carried along.
run gsettings set org.gnome.desktop.app-folders folder-children "['Utilities', 'System', 'Office']"

app_folder Utilities 'X-GNOME-Shell-Utilities.directory' true "[
  'org.gnome.Decibels.desktop', 'org.gnome.Connections.desktop', 'org.gnome.Papers.desktop',
  'org.gnome.font-viewer.desktop', 'org.gnome.Loupe.desktop', 'org.gnome.Snapshot.desktop',
  'org.gnome.Characters.desktop', 'org.gnome.Showtime.desktop', 'org.fedoraproject.MediaWriter.desktop',
  'org.gnome.Contacts.desktop', 'org.gnome.clocks.desktop', 'org.gnome.Maps.desktop',
  'org.gnome.SimpleScan.desktop', 'org.gnome.Calculator.desktop', 'org.gnome.Software.desktop',
  'org.gnome.Calendar.desktop', 'org.gnome.Nautilus.desktop'
]"

# Tour, Yelp (Help) and Weather are uninstalled by apps.sh, so they are left out
# here — keep the two in sync if you change that set.
app_folder System 'X-GNOME-Shell-System.directory' true "[
  'org.gnome.baobab.desktop', 'org.gnome.DiskUtility.desktop', 'org.gnome.Logs.desktop',
  'org.freedesktop.MalcontentControl.desktop', 'org.gnome.SystemMonitor.desktop',
  'org.gnome.Settings.desktop', 'btrfs-assistant.desktop', 'org.gnome.tweaks.desktop'
]"

app_folder Office 'Office' false "[
  'libreoffice-impress.desktop', 'libreoffice-calc.desktop', 'libreoffice-writer.desktop',
  'libreoffice-base.desktop', 'libreoffice-draw.desktop', 'libreoffice-math.desktop'
]"

# ─────────────────────────────────────────────
# Display Behavior
# ─────────────────────────────────────────────

# Prevent suspend when the laptop lid is closed
step "Configuring lid-close behavior"
run sudo mkdir -p /etc/systemd/logind.conf.d
cat <<'EOF' | sudo tee /etc/systemd/logind.conf.d/99-ignore-lid.conf >/dev/null
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF
say "wrote /etc/systemd/logind.conf.d/99-ignore-lid.conf"

# Also set the power button to show the interactive dialog instead of shutting down immediately
run gsettings set org.gnome.settings-daemon.plugins.power power-button-action 'interactive'
say "reboot required for the lid-close change to take effect"
