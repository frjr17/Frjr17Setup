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
run sudo snapper -c root create-config /
run sudo snapper -c home create-config /home

run sudo restorecon -RFv /.snapshots
run sudo restorecon -RFv /home/.snapshots

run sudo snapper -c root set-config ALLOW_USERS=$USER SYNC_ACL=yes
run sudo snapper -c home set-config ALLOW_USERS=$USER SYNC_ACL=yes

echo 'PRUNENAMES = ".snapshots"' | sudo tee -a /etc/updatedb.conf >/dev/null
say "excluded .snapshots from updatedb"

# ─────────────────────────────────────────────
# grub-btrfs
# ─────────────────────────────────────────────
step "Installing grub-btrfs"
cd /tmp
rm -rf grub-btrfs   # rerun-safe: git clone aborts under set -e if the dir exists
run git clone https://github.com/Antynea/grub-btrfs
cd grub-btrfs

sed -i.bkp \
  -e '/^#GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS=/a \
GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS="rd.live.overlay.overlayfs=1"' \
  -e '/^#GRUB_BTRFS_GRUB_DIRNAME=/a \
GRUB_BTRFS_GRUB_DIRNAME="/boot/grub2"' \
  -e '/^#GRUB_BTRFS_MKCONFIG=/a \
GRUB_BTRFS_MKCONFIG=/usr/bin/grub2-mkconfig' \
  -e '/^#GRUB_BTRFS_SCRIPT_CHECK=/a \
GRUB_BTRFS_SCRIPT_CHECK=grub2-script-check' \
  config
say "patched config for Fedora's grub2 paths"

run sudo make install
run sudo systemctl enable --now grub-btrfsd.service

cd ..
rm -rf grub-btrfs

# ─────────────────────────────────────────────
# Automatic Snapshots
# ─────────────────────────────────────────────
step "Enabling automatic snapshots"
run sudo snapper -c home set-config TIMELINE_CREATE=no
run sudo systemctl enable --now snapper-timeline.timer
run sudo systemctl enable --now snapper-cleanup.timer
