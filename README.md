# My Own Scripts

Small collection of Bash scripts for setting up a Fedora desktop, configuring GNOME shortcuts, and bootstrapping a development shell.

## 📦 What's Inside

- `dev.sh` — Bootstraps a development environment. Installs common developer packages, runtime managers (e.g., `nvm` for Node), language tooling, and then calls the shell setup to ensure your interactive environment is ready. Run from the repo root with `./dev.sh`.

- `favoriteShell.sh` — Sets up your preferred interactive shell. Installs/configures Zsh, Oh My Zsh, Powerlevel10k theme, required fonts (from `fonts/`), common aliases, and writes Git identity values (from `.env`) to your global Git config. Review before running as it updates shell defaults.

- `fedoraSetup.sh` — Installs and configures a Fedora desktop environment. Installs packages, Flatpaks, GNOME extensions, themes, and other desktop utilities. Intended for setting up a fresh Fedora workstation; it may change system packages and settings.

- `ui.sh` — Applies GNOME UI tweaks and keyboard bindings. Uses `gsettings`/`dconf` to create or update workspace behavior, shortcut mappings, and window-management preferences.

- `googleDrive.sh` — Utility for configuring or syncing Google Drive resources. Depending on your system tools (e.g., `rclone`), this script helps set up authentication and mount/sync workflows. Inspect the script for the exact flow before use.

- `bravePwa.sh` — Installs/uninstalls web apps (WhatsApp, Work WhatsApp, ChatGPT, Claude, Canva, Notion) as desktop launchers that open in Brave app-mode windows. Usage: `./bravePwa.sh install|uninstall|list [app ...]`. Each app runs as its own isolated Brave instance (own `--user-data-dir`) so it gets a correct, separate dock/taskbar icon on Wayland instead of grouping under Brave. On first install (with Brave closed) each app's data dir is seeded from your main Brave profile — via copy-on-write reflinks on Btrfs, so it's near-free on disk — carrying your logins, extensions and settings across. Work WhatsApp is excluded from seeding (see `NOSEED` in the script) so it starts logged out — scan a second number's QR to run a WhatsApp account separate from your main one.

- `fedora-harden.sh` — Security hardening baseline for a personal Fedora Workstation laptop (single user, GNOME, developer machine). Dry-run by default; see [🔐 Hardening](#-hardening) below.

- `snapper.sh` — Helpers around `snapper` (Btrfs snapshot management). Provides shortcuts for creating, listing, and cleaning snapshots so you can manage system rollbacks. Run with care on systems using Btrfs.

- `fonts/` — Local font archives referenced by the shell setup. Place required font ZIPs here so `favoriteShell.sh` can install them.

- Other scripts (one-off helpers) — Review each script's header comments for usage examples and options before running. Many scripts expect to be executed from the repository root.

## ✅ Requirements

These scripts are written for Fedora/Linux and assume a GNOME-based desktop for the UI setup.

Common dependencies include:

- `bash`
- `sudo`
- `dnf`
- `git`
- `curl`
- `unzip`

Some scripts also expect tools such as `zsh`, `pipx`, `flatpak`, `snap`, `gnome-extensions`, and `firefox` to be available or installable on the system.

## ▶️ Usage

Run the scripts directly from the repository root:

```bash
chmod +x *.sh
./favoriteShell.sh
./dev.sh
./ui.sh
./fedoraSetup.sh
```

## 📝 Notes

- `favoriteShell.sh` updates global Git config values and changes your default shell to Zsh. 🔐
- `fedoraSetup.sh` installs desktop apps, GNOME extensions, and theming packages, so it can take a while. ⏳
- `dev.sh` depends on `favoriteShell.sh` and installs Node.js through `nvm`. 📦
- The font installation step expects `FiraCodeNF.zip` and `OperatorMonoLig.zip` inside `fonts/`. 🗂️

## ⚠️ Safety

These scripts make system-wide changes. Review them before running, especially if you want to adjust package lists, shell settings, or GNOME keybindings.

## 🔐 Hardening

`fedora-harden.sh` targets a **personal Fedora Workstation laptop**. Threat model: lost/stolen laptop, untrusted Wi-Fi, malicious downloads. Not a server — server/enterprise controls (banners, password aging, umask, remote logging, USB lockdown, most sysctl tweaks) are intentionally omitted; the script header explains each.

| Section     | Action                                                                                          |
| ----------- | ----------------------------------------------------------------------------------------------- |
| `preflight` | Verify Fedora, non-root, sudo, network. Always runs.                                             |
| `report`    | Read-only status: firewall, SELinux, LUKS, Secure Boot, dev services, auto-updates. Always runs. |
| `updates`   | `dnf upgrade`, install + enable `dnf-automatic` with `apply_updates = yes`.                      |
| `firewall`  | Default zone → `public` (Fedora's default zone opens all ports >1024).                           |
| `audit`     | Lynis audit, saved to a file, laptop-relevant suggestions only.                                   |
| `rkhunter`  | Install, fix `WEB_CMD`, set baseline, run check, label benign warnings.                          |
| `aide`      | Init file-integrity database (skipped if one exists; `--force` to redo).                         |
| `services`  | Offer to disable `httpd`/`mariadb`/`mysqld` at boot — asks per service, never touches docker.     |
| `helpers`   | Install `sec-check` and `sec-rebaseline` to `/usr/local/bin`.                                     |

It **never** disables SELinux, and only _reports_ disk-encryption and Secure Boot status (those need a reinstall / firmware access).

```bash
./fedora-harden.sh                # dry run (default) — prints, changes nothing
./fedora-harden.sh --apply        # make changes, confirm each section
./fedora-harden.sh --apply --yes  # no section prompts (service disables still ask)
--only <section>                  # run just one section (repeatable)
--skip <section>                  # skip a section (repeatable)
--force                           # re-init AIDE db even if one exists
```

Idempotent — safe to re-run any time; already-correct items print `[ok]`. Edited configs are backed up to `<file>.bak-<timestamp>` and listed at the end. Everything is logged to `/var/log/fedora-harden.log`.

Maintenance rhythm:

```bash
sec-check        # BEFORE a system update — verify nothing is off
sec-rebaseline   # AFTER a system update — accept new files as the trusted baseline
```

Skip the rebaseline and every future check drowns in update noise; skip the check and you can't tell an update's changes from an intruder's.

## 🔧 Configuration

- Copy `.env.example` to `.env` and fill in your values before running scripts that rely on Git identity or other environment variables:

```bash
cp .env.example .env
# Edit .env and provide values for:
# GITHUB_NAME (e.g., Jane Doe)
# GITHUB_USERNAME (e.g., janedoe)
# GITHUB_EMAIL (e.g., jane@example.com)
```

The repository includes a commented `.env.example` with placeholders and descriptions to help you set these values.

