#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"

# ─────────────────────────────────────────────
# Install Packages
# ─────────────────────────────────────────────
step "Updating system packages"
run sudo dnf update -y

step "Installing snapper and friends"
run sudo dnf install snapper libdnf5-plugin-actions btrfs-assistant inotify-tools git make -y

# ─────────────────────────────────────────────
# DNF Snapper Actions Plugin
# ─────────────────────────────────────────────
step "Writing the DNF snapper actions plugin"
sudo bash -c "cat > /etc/dnf/libdnf5-plugins/actions.d/snapper.actions" <<'EOF'
# Get snapshot description
pre_transaction::::/usr/bin/sh -c echo\ "tmp.cmd=$(ps\ -o\ command\ --no-headers\ -p\ '${pid}')"

# Creates pre snapshot before the transaction and stores the snapshot number in the "tmp.snapper_pre_number"  variable.
pre_transaction::::/usr/bin/sh -c echo\ "tmp.snapper_pre_number=$(snapper\ create\ -t\ pre\ -c\ number\ -p\ -d\ '${tmp.cmd}')"

# If the variable "tmp.snapper_pre_number" exists, it creates post snapshot after the transaction and removes the variable "tmp.snapper_pre_number".
post_transaction::::/usr/bin/sh -c [\ -n\ "${tmp.snapper_pre_number}"\ ]\ &&\ snapper\ create\ -t\ post\ --pre-number\ "${tmp.snapper_pre_number}"\ -c\ number\ -d\ "${tmp.cmd}"\ ;\ echo\ tmp.snapper_pre_number\ ;\ echo\ tmp.cmd
EOF
say "wrote /etc/dnf/libdnf5-plugins/actions.d/snapper.actions"

# ─────────────────────────────────────────────
# Snapper Configs
# ─────────────────────────────────────────────
step "Creating snapper configs for / and /home"
# create-config errors out when the config already exists.
for cfg in root:/ home:/home; do
  name=${cfg%%:*} path=${cfg#*:}
  if sudo snapper -c "$name" get-config >/dev/null 2>&1; then
    say "snapper config '$name' already exists"
  else
    run sudo snapper -c "$name" create-config "$path"
  fi
done

run sudo restorecon -RFv /.snapshots
run sudo restorecon -RFv /home/.snapshots

run sudo snapper -c root set-config "ALLOW_USERS=$USER" SYNC_ACL=yes
run sudo snapper -c home set-config "ALLOW_USERS=$USER" SYNC_ACL=yes

# Appended a duplicate line on every run before the guard.
if grep -q '^PRUNENAMES' /etc/updatedb.conf; then
  say ".snapshots already excluded from updatedb"
else
  echo 'PRUNENAMES = ".snapshots"' | sudo tee -a /etc/updatedb.conf >/dev/null
  say "excluded .snapshots from updatedb"
fi

# ─────────────────────────────────────────────
# grub-btrfs
# ─────────────────────────────────────────────
step "Installing grub-btrfs"
if systemctl is-enabled grub-btrfsd.service >/dev/null 2>&1; then
  cached "grub-btrfs already installed and enabled"
else
  src="$BK_SCRATCH/grub-btrfs"
  run git clone --depth=1 https://github.com/Antynea/grub-btrfs "$src"

  sed -i.bkp \
    -e '/^#GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS=/a \
GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS="rd.live.overlay.overlayfs=1"' \
    -e '/^#GRUB_BTRFS_GRUB_DIRNAME=/a \
GRUB_BTRFS_GRUB_DIRNAME="/boot/grub2"' \
    -e '/^#GRUB_BTRFS_MKCONFIG=/a \
GRUB_BTRFS_MKCONFIG=/usr/bin/grub2-mkconfig' \
    -e '/^#GRUB_BTRFS_SCRIPT_CHECK=/a \
GRUB_BTRFS_SCRIPT_CHECK=grub2-script-check' \
    "$src/config"
  say "patched config for Fedora's grub2 paths"

  run sudo make -C "$src" install
  run sudo systemctl enable --now grub-btrfsd.service
fi

# ─────────────────────────────────────────────
# Automatic Snapshots
# ─────────────────────────────────────────────
step "Enabling automatic snapshots"
run sudo snapper -c home set-config TIMELINE_CREATE=no
run sudo systemctl enable --now snapper-timeline.timer
run sudo systemctl enable --now snapper-cleanup.timer
