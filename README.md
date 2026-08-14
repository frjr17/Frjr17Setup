# My Own Scripts

Small collection of Bash scripts for setting up a Fedora desktop, configuring GNOME shortcuts, and bootstrapping a development shell.

Every script is idempotent and runs unattended — see [🤖 Unattended runs](#-unattended-runs).

## 📦 What's Inside

- `setup.sh` — **Start here.** Runs the provisioning scripts in dependency order, unattended. A stage that fails doesn't stop the rest; failures are listed at the end and fixed by re-running. Deliberately excludes `fedoraHarden.sh` and `googleDrive.sh` — see its header for why.

- `gnomeSettings.sh` — Enables the RPM Fusion repositories, then applies the GNOME desktop configuration: keyboard shortcuts (monitor/workspace movement, `Super+E` for the file explorer, `Super+N` for the message tray), the dock contents, the app grid folders, and lid-close/power-button behavior. Must run before `apps.sh`, which needs RPM Fusion.

  The dock is GNOME's `favorite-apps` list and the grid folders are `org.gnome.desktop.app-folders` — both are plain `gsettings` keys, so editing the lists in the script is all it takes to rearrange them. Favourites naming an app that isn't installed yet are ignored by the shell and appear on their own once it is, which is why this can run before `apps.sh` and `bravePwa.sh`.

- `apps.sh` — Installs the desktop applications: snapd, multimedia codecs, LibreOffice, Thunderbird, Muse Sounds, Brave, VS Code, Docker Desktop, Telegram, MuseScore, Discord, Spotify — and removes the preinstalled Firefox. The two third-party direct downloads (Muse Sounds, Docker Desktop) warn and continue if their URL has gone stale.

- `dev.sh` — Bootstraps a development environment: Vim, `nvm` + Node LTS, the repo's `.npmrc`, and Docker CE (replacing the distro packages).

- `favoriteShell.sh` — Sets up Zsh as your shell: Oh My Zsh, Powerlevel10k, syntax highlighting and autosuggestions, the fonts from `fonts/`, an alias block appended to `.zshrc`, and your global Git identity. See [🔧 Configuration](#-configuration) for how to supply that identity.

- `whitesurTheme.sh` — Installs the WhiteSur cursors, icon theme and GTK theme, applies the GDM tweak, and selects `WhiteSur-Dark-purple`. Run before `gnomeExtensions.sh`, which selects the same theme for the shell.

- `gnomeExtensions.sh` — Installs `gnome-extensions-cli` and the Extension Manager GUI, then installs, enables and configures the GNOME Shell extensions (Blur My Shell, Dash to Dock, Logo Menu, Just Perfection and friends).

- `googleDrive.sh` — Sets up continuous two-way sync between `~/GoogleDrive` and a Google Drive `rclone` remote, via a systemd user timer with desktop notifications. Requires an existing remote (`rclone config`, an interactive OAuth flow). `--init` runs the first baseline; `--yes` skips its confirmation.

- `bravePwa.sh` — Installs/uninstalls web apps (WhatsApp, Work WhatsApp, ChatGPT, Claude, Canva, Notion) as desktop launchers that open in Brave app-mode windows. Usage: `./bravePwa.sh install|uninstall|list [app ...]`. Each app runs as its own isolated Brave instance (own `--user-data-dir`) so it gets a correct, separate dock/taskbar icon on Wayland instead of grouping under Brave. On first install (with Brave closed) each app's data dir is seeded from your main Brave profile — via copy-on-write reflinks on Btrfs, so it's near-free on disk — carrying your logins, extensions and settings across. Work WhatsApp is excluded from seeding (see `NOSEED` in the script) so it starts logged out — scan a second number's QR to run a WhatsApp account separate from your main one.

- `fedoraHarden.sh` — Security hardening baseline for a personal Fedora Workstation laptop (single user, GNOME, developer machine). Dry-run by default; see [🔐 Hardening](#-hardening) below.

- `snapper.sh` — Sets up Btrfs snapshots so the rest of the provision is reversible: installs `snapper` and `btrfs-assistant`, adds the DNF plugin that takes a pre/post snapshot around every transaction, creates the `root` and `home` configs, installs `grub-btrfs` (patched for Fedora's grub2 paths) so snapshots appear in the boot menu, and enables the timeline and cleanup timers. **Btrfs only.** `setup.sh` runs it first, before anything else installs packages.

- `log.sh` — Shared progress output, sourced by every other script. Prints in the same shape as `docker build --progress=plain`, so a run reads as numbered steps with their own timings:

  ```
  #3 [3/9] Installing Docker CE
  #3 0.412 Installing: docker-ce  x86_64  28.0.1-1.fc44
  #3 DONE 8.1s
  #4 [4/9] Ensuring pipx is available
  #4 0.002 pipx already installed
  #4 CACHED
  [+] Building 45.2s (9/9) FINISHED
  ```

  A failing step ends the run with the docker-style `ERROR: failed to solve: <step>: exit code N` block. `test_log.sh` checks both shapes — run it after touching `log.sh`.

  It also owns two things every script depends on: the sudo timestamp (claimed once, then kept warm so no step can re-prompt) and a scratch directory. Use `tmp=$(bk_scratch)` for downloads and clones — do **not** add your own `trap ... EXIT`, it replaces `log.sh`'s and the run loses its DONE/FINISHED and ERROR output.

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

Provision everything in the right order:

```bash
./setup.sh
```

It asks for your Git identity and your sudo password up front, then runs for
roughly 40 minutes without needing you. Pre-set any of the three to skip that
question:

```bash
GITHUB_NAME="Jane Doe" GITHUB_USERNAME=janedoe GITHUB_EMAIL=jane@example.com ./setup.sh
```

Or run any script on its own, from the repository root:

```bash
./snapper.sh         # Btrfs snapshots                  (first — makes the rest reversible)
./gnomeSettings.sh   # RPM Fusion + GNOME keybindings   (before apps.sh)
./apps.sh            # desktop applications
./favoriteShell.sh   # Zsh, Oh My Zsh, fonts, Git identity
./dev.sh             # Node, Docker
./whitesurTheme.sh   # GTK theme                        (before gnomeExtensions.sh)
./gnomeExtensions.sh # GNOME Shell extensions
```

## 🤖 Unattended runs

The scripts are built to be started and walked away from:

- **Idempotent.** Every one exits 0 on a second run; already-done work prints `CACHED` instead of being redone. A run that dies partway is resumed by running it again.
- **Never prompts silently.** Commands under `run` get `/dev/null` on stdin, so anything that would wait for input fails immediately and visibly instead of hanging on a prompt trapped in the output pipe.
- **`NONINTERACTIVE=1`** makes every prompt take its safe default: `googleDrive.sh` skips its baseline confirmation, `fedoraHarden.sh` answers *No* to each service disable, and `favoriteShell.sh` requires the Git identity up front rather than asking. `setup.sh` sets it for you.
- **Sudo fails fast.** Under `NONINTERACTIVE=1`, a script needing sudo without a cached timestamp exits at once telling you to run `sudo -v` — it never blocks. Once claimed, a background refresh keeps it alive so a long `dnf` step can't cause a second prompt.

`setup.sh` front-loads both of those: it collects the Git identity and calls `sudo -v` in its preamble, then sets `NONINTERACTIVE=1` for every stage. So a full provision asks its questions in the first ten seconds and nothing after.

Running a single script directly instead? `favoriteShell.sh` prompts for whatever identity it's missing, also before doing any work. Everything else needs only a cached sudo timestamp — `sudo -v`, then start it.

## 📝 Notes

- `favoriteShell.sh` updates global Git config values and changes your default shell to Zsh. 🔐
- `apps.sh` installs desktop apps and Flatpaks, so it can take a while. ⏳
- The font installation step expects `FiraCodeNF.zip` and `OperatorMonoLig.zip` inside `fonts/`. 🗂️
- `bravePwa.sh install` needs Brave fully closed the first time — it copies your profile into each app. 🦁

## ⚠️ Safety

These scripts make system-wide changes. Review them before running, especially if you want to adjust package lists, shell settings, or GNOME keybindings.

## 🔐 Hardening

`fedoraHarden.sh` targets a **personal Fedora Workstation laptop**. Threat model: lost/stolen laptop, untrusted Wi-Fi, malicious downloads. Not a server — server/enterprise controls (banners, password aging, umask, remote logging, USB lockdown, most sysctl tweaks) are intentionally omitted; the script header explains each.

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
./fedoraHarden.sh                # dry run (default) — prints, changes nothing
./fedoraHarden.sh --apply        # make changes, confirm each section
./fedoraHarden.sh --apply --yes  # no section prompts (service disables still ask)
--only <section>                  # run just one section (repeatable)
--skip <section>                  # skip a section (repeatable)
--force                           # re-init AIDE db even if one exists
```

Idempotent — safe to re-run any time; already-correct items print `CACHED`. Edited configs are backed up to `<file>.bak-<timestamp>` and listed at the end. Everything is logged to `/var/log/fedora-harden.log`.

Maintenance rhythm:

```bash
sec-check        # BEFORE a system update — verify nothing is off
sec-rebaseline   # AFTER a system update — accept new files as the trusted baseline
```

Skip the rebaseline and every future check drowns in update noise; skip the check and you can't tell an update's changes from an intruder's.

## 🔧 Configuration

`favoriteShell.sh` needs a Git identity. It takes it from flags, then the environment, then an interactive prompt — so an unattended run must supply one of the first two:

```bash
./favoriteShell.sh --name "Jane Doe" --username janedoe --email jane@example.com

GITHUB_NAME="Jane Doe" GITHUB_USERNAME=janedoe GITHUB_EMAIL=jane@example.com ./favoriteShell.sh
```

`setup.sh` passes the environment straight through, so exporting those three variables covers a full provision.

`googleDrive.sh` is configured the same way — `REMOTE_NAME`, `LOCAL_DIR`, `TIMER_INTERVAL` and `MAX_DELETE`, all documented in its `--help`.

