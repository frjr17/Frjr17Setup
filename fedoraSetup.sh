#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"

# ─────────────────────────────────────────────
# Keyboard Commands
# ─────────────────────────────────────────────

step "Setting custom keyboard shortcuts"

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

# Notifications
run gsettings set org.gnome.shell.keybindings toggle-message-tray "['<Super>n']"

# Settings
run gsettings set org.gnome.settings-daemon.plugins.media-keys control-center "['<Super>i']"

# "Open File Explorer" shortcut (custom one)
step "Binding Super+E to the file explorer"
run gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ name 'Open File Explorer'
run gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ command 'nautilus'
run gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding '<Super>e'

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
