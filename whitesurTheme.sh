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