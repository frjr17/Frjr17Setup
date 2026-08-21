#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"

# ─────────────────────────────────────────────
# npm (installed by dev.sh via nvm)
# ─────────────────────────────────────────────
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    # shellcheck disable=SC1091
    \. "$NVM_DIR/nvm.sh"
fi

step "Checking for npm"
if command -v npm >/dev/null 2>&1; then
    cached "npm found ($(npm --version))"
else
    warn "npm not found — run ./dev.sh first to install Node.js via nvm"
    exit 1
fi

# ─────────────────────────────────────────────
# Claude Code CLI
# ─────────────────────────────────────────────
step "Installing Claude Code CLI"
if command -v claude >/dev/null 2>&1; then
    cached "claude already installed ($(claude --version 2>/dev/null || echo 'version unknown'))"
else
    run npm install -g @anthropic-ai/claude-code
fi

# ─────────────────────────────────────────────
# Codex CLI
# ─────────────────────────────────────────────
step "Installing Codex CLI"
if command -v codex >/dev/null 2>&1; then
    cached "codex already installed ($(codex --version 2>/dev/null || echo 'version unknown'))"
else
    run npm install -g @openai/codex
fi

step "Exporting AI CLI environment"
say "claude: $(claude --version 2>/dev/null || echo 'not on PATH yet')"
say "codex: $(codex --version 2>/dev/null || echo 'not on PATH yet')"
