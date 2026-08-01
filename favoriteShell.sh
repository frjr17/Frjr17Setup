#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"

# ─────────────────────────────────────────────
# Constants & Variables
# ─────────────────────────────────────────────

GITHUB_NAME="" GITHUB_USERNAME="" GITHUB_EMAIL=""

usage() {
  cat <<EOF
Usage: $0 [--name NAME] [--username USERNAME] [--email EMAIL]

Any Git identity value not passed as a flag is prompted for interactively.
For automated (non-interactive) runs, pass all three flags.
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)     GITHUB_NAME="$2";     shift 2 ;;
    --username) GITHUB_USERNAME="$2"; shift 2 ;;
    --email)    GITHUB_EMAIL="$2";    shift 2 ;;
    -h|--help)  usage ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
done

# Prompt for anything still missing; fail fast if we can't (automated run w/o flags).
prompt_missing() {
  local var="$1" label="$2" flag="${1#GITHUB_}"
  [[ -n "${!var}" ]] && return 0
  [[ -t 0 ]] || { echo "Missing --${flag,,} and no terminal to prompt." >&2; exit 1; }
  read -rp "$label: " "$var"
  [[ -n "${!var}" ]] || { echo "$label is required." >&2; exit 1; }
}
prompt_missing GITHUB_NAME     "Git full name"
prompt_missing GITHUB_USERNAME "GitHub username"
prompt_missing GITHUB_EMAIL    "Git email"

FONTS_DIR="$SCRIPT_DIR/fonts"
FONTS_DEST="$HOME/.local/share/fonts"

ZSHRC="$HOME/.zshrc"
P10K_FILE="$HOME/.p10k.zsh"

# ─────────────────────────────────────────────
# Git Configuration
# ─────────────────────────────────────────────

step "Configuring Git identity"
run git config --global user.name "$GITHUB_NAME"
run git config --global user.username "$GITHUB_USERNAME"
run git config --global user.email "$GITHUB_EMAIL"

# ─────────────────────────────────────────────
# Install Fonts
# ─────────────────────────────────────────────

step "Installing fonts from $FONTS_DIR"
mkdir -p "$FONTS_DEST"

if [[ -d "$FONTS_DIR" ]]; then
    run unzip -o "$FONTS_DIR/FiraCodeNF.zip" -d "$FONTS_DIR"
    run unzip -o "$FONTS_DIR/OperatorMonoLig.zip" -d "$FONTS_DIR"
    mv "$FONTS_DIR"/*.ttf "$FONTS_DEST" || true
    mv "$FONTS_DIR"/*.otf "$FONTS_DEST" || true
    say "installed into $FONTS_DEST"
else
    cached "fonts directory '$FONTS_DIR' not found; skipping"
fi

# ─────────────────────────────────────────────
# Install Packages
# ─────────────────────────────────────────────

step "Installing shell and build packages"
run sudo dnf install -y \
    zsh curl ruby ruby-devel \
    rubygem-{irb,rake,rbs,rexml,typeprof,test-unit} ruby-bundled-gems \
    make automake gcc gcc-c++ kernel-devel

step "Installing colorls"
run sudo gem install colorls

# ─────────────────────────────────────────────
# Zsh, Oh My Zsh, and Plugins
# ─────────────────────────────────────────────

step "Installing Oh My Zsh"
export RUNZSH=no
run sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

step "Installing Zsh theme and plugins"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
run git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
run git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
run git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"

# ─────────────────────────────────────────────
# Zsh Configuration
# ─────────────────────────────────────────────

step "Configuring $ZSHRC"
sed -i 's/^plugins=.*/plugins=(git zsh-syntax-highlighting zsh-autosuggestions)/' "$ZSHRC"
sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ZSHRC"
say "set theme powerlevel10k and plugins (git, syntax-highlighting, autosuggestions)"

cat << 'EOF' >> "$ZSHRC"

# Custom Aliases and Enhancements
if command -v colorls &> /dev/null; then
    alias ls="colorls"
    alias la="colorls -al"
fi

alias update='sudo dnf update && sudo dnf upgrade && sudo dnf autoremove'
alias rmdir='rm -rf'
alias open='xdg-open'
alias python='python3'
alias venv_activate='source ./venv/bin/activate'
alias create_venv='python -m venv venv && venv_activate'

outlinepdf() {
  if [[ $# -ne 1 ]]; then
    echo "Usage: outlinepdf file.pdf"
    return 1
  fi

  local input="$1"

  if [[ ! -f "$input" ]]; then
    echo "File not found: $input"
    return 1
  fi

  if [[ "${input:l}" != *.pdf ]]; then
    echo "Input must be a PDF: $input"
    return 1
  fi

  local dir="${input:h}"
  local name="${input:t}"
  local backup="${dir}/${name:r}.original.pdf"
  local temp="${dir}/.${name:r}.outlined.tmp.pdf"

  cp "$input" "$backup"

  gs \
    -o "$temp" \
    -sDEVICE=pdfwrite \
    -dNoOutputFonts \
    -dNOPAUSE \
    -dBATCH \
    -dSAFER \
    "$input"

  mv "$temp" "$input"

  echo "Outlined PDF saved as: $input"
  echo "Original backup saved as: $backup"
}
EOF
say "appended aliases and the outlinepdf helper"

# ─────────────────────────────────────────────
# Set Zsh as Default Shell
# ─────────────────────────────────────────────

step "Setting Zsh as the default shell for $USER"
chsh -s "$(which zsh)" "$USER"   # not wrapped: chsh prompts for your password
say "restart your terminal or run: exec zsh"
