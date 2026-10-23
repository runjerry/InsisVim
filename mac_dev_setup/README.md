# Remote Linux Development Setup (tested on Ubuntu24.04)

This directory contains setup scripts for configuring remote Linux machines.

## Scenario

**Local:** macOS with Alacritty, or cmux/Ghostty
**Remote:** Linux machine accessed via SSH, running Fish shell, tmux, and Neovim

**Goal:** Copy from remote Neovim with `<C-c>` and paste to local macOS clipboard with `Cmd+V`

## Prerequisites

### On Local macOS (Already Configured)

Your local macOS machine should have:

1. **Alacritty** with OSC 52 enabled (`~/.config/alacritty/alacritty.toml`):
   ```toml
   [terminal]
   osc52 = "CopyPaste"
   ```

2. **This configuration** already working for local development

### On Remote Linux (To Be Configured)

The setup script will configure the remote machine automatically.

## Quick Start

### 1. Choose the Script for Your Remote Machine

Use `remote-setup` for the validated RunPod/Docker workflow and `linux-server-setup` for native Linux servers. Each branch contains its own Fish and tmux templates. When provisioning a container from a checkout, use the `remote-setup` checkout: scripts prefer adjacent template files, so running a container script from the Linux server branch would also use that branch's templates.

For a **native Linux server or VM** (tested on Ubuntu 24.04 x86_64), run as the account you want to configure:

```bash
curl -fLO https://raw.githubusercontent.com/runjerry/InsisVim/linux-server-setup/mac_dev_setup/setup_remote_linux.sh
bash setup_remote_linux.sh
# Unattended installation of all optional tools:
bash setup_remote_linux.sh -y
```

To review the native script and templates before running:

```bash
git clone --branch linux-server-setup --single-branch https://github.com/runjerry/InsisVim.git
bash InsisVim/mac_dev_setup/setup_remote_linux.sh -y
```

Root is supported directly. For a regular user, run without `sudo`; the script uses `sudo` only for package installation and account shell changes. Running the whole script with `sudo` would configure the wrong home directory and is rejected.

The native script includes the tools and cmux workflow from the Phase A container script, with these host-specific behaviors:

| Area | Native Linux behavior |
| --- | --- |
| Fish | Uses `chsh`; only cmux-injected Bash sessions hand off to Fish after cmux initialization |
| Python | Installs `python-lsp-server`, Black and Magic Wormhole using isolated `uv tool` environments; keeps system Python protection enabled |
| Existing configuration | Preserves Neovim data, installed Neovim, Git identity, Claude/Codex credentials, providers and explicit editor/notification/TUI preferences in `-y` mode |
| Backups | Saves original files before changes under `~/.local/state/insis-setup/backups/<timestamp>-<pid>/` |
| Plugins | Installs Fisher, TPM plugins, enabled Neovim plugins, language tools and syntax parsers automatically |
| Remote workflow | Includes cmux notifications, Fish working-directory reporting, paste-mode prompt editing and `mdview` helpers |

Fish and tmux configuration templates are refreshed with backups. The Neovim configuration is cloned over HTTPS only when absent. The native script fetches templates and new Neovim checkouts from `linux-server-setup` by default. `NVIM_CONFIG_REPO` and `NVIM_CONFIG_BRANCH` can override the default GitHub repository/branch, and `INSIS_GIT_NAME` / `INSIS_GIT_EMAIL` override the default identity when none exists. Re-running `-y` retries installation without deleting Neovim directories or forcing a Neovim reinstall.

Neovim remains pinned to **v0.9.5**, matching the repository's existing plugin lockfile; its x86_64 archive and the optional tmux 3.4 source build are SHA-256 checked. Other architectures fail explicitly instead of installing an incompatible binary. Existing Codex TOML is validated before merging; this requires Python 3.11+ (included with Ubuntu 24.04).

The native `mdview <file.md> [port]` helper restricts previews to `127.0.0.1`. Use cmux port forwarding, or `ssh -L 5173:127.0.0.1:5173 <host>` for ordinary SSH, then open `http://localhost:5173` on your Mac. Use `mdview-status` and `mdview-stop [port]` to manage previews. The pinned `mdprev` package has no host option, so the native helper uses a Node preload scoped to the preview process to enforce the bind address. Existing custom helper files are preserved.

For a **RunPod/Docker container**, use the Phase A script:

SSH to your remote Linux machine, then download the setup script:

```bash
# Option 1: Download the script directly
curl -O https://raw.githubusercontent.com/runjerry/InsisVim/remote-setup/mac_dev_setup/setup_remote_container_cmux_phase_a.sh
# or use wget
wget https://raw.githubusercontent.com/runjerry/InsisVim/remote-setup/mac_dev_setup/setup_remote_container_cmux_phase_a.sh

# Alternatively, clone the validated container branch:
git clone --branch remote-setup --single-branch https://github.com/runjerry/InsisVim.git
# Then run InsisVim/mac_dev_setup/setup_remote_container_cmux_phase_a.sh.
```

### 2. Run the Container Setup Script

```bash
chmod +x setup_remote_container_cmux_phase_a.sh
./setup_remote_container_cmux_phase_a.sh
```

The script will:

- Detect your Linux distribution and package manager
- Install tmux (if not present)
- Create `~/.tmux.conf` with OSC 52 passthrough configuration
- Optionally install Fish shell, Neovim, Claude Code, and Codex CLI
- Install `~/.claude/settings.json` from `claude_settings.json` when Claude Code is available
- Install `~/.codex/AGENTS.md` with Markdown math formatting instructions when Codex CLI is available
- Create new `~/.codex/config.toml` files with cmux notifications and terminal scrollback enabled
- Configure the `Ctrl+G` editor in Codex and Claude Code to open Neovim in paste mode for multiline prompts
- Guide you through next steps

### 3. Install Tmux and Neovim Plugins

- The native script installs tmux and Neovim plugins during setup.
- For the container scripts, install tmux plugins with `Ctrl+a` then `I` (Shift+i).
- The Phase A script also bootstraps Neovim plugins; other setups install them on first launch.

### 4. Test the Setup

1. Start tmux: `tmux`
2. Open Neovim: `nvim`
3. Check clipboard provider: `:checkhealth provider`
4. Select text in visual mode and press `<C-c>`
5. On your local macOS, press `Cmd+V` to paste

## What Gets Configured

### Claude Code Settings (`~/.claude/settings.json`)

All three setup scripts install this directory's `claude_settings.json` when Claude Code is available and the settings file is absent. Standalone downloads fetch templates from the configured GitHub repository and branch. Existing settings are preserved. The native script also adds missing `env.EDITOR` and `env.VISUAL` entries with a backup, without replacing credentials, provider settings or existing editor preferences.

The template sets both `env.EDITOR` and `env.VISUAL` to `nvim-prompt-editor`, reusing the helper installed during Fish setup. The shared `fish_config.fish` adds `~/.local/bin` to `PATH`, so the command works for any username without a hard-coded home directory. Pressing `Ctrl+G` in Claude Code opens Neovim with `set paste` enabled to preserve multiline indentation. For an existing machine, merge these two environment settings into `~/.claude/settings.json`, ensure the helper is on `PATH`, and restart Claude Code.

Keep `code` out of the helper's command name: Claude Code 2.1.292 identifies VS Code by that substring, so `codex-prompt-editor` is misclassified as a graphical editor and does not use the terminal editor handoff.

The later cmux integration step adds missing `Stop` and `PostToolUse` (`Task`) notification hooks to `settings.json`, preserving other settings and creating a timestamped backup whenever it changes the file.

### Codex Instructions (`~/.codex/AGENTS.md`)

After installing Codex CLI, or detecting an existing installation, the native and Phase A scripts copy this directory's `AGENTS.md` to `~/.codex/AGENTS.md`. Standalone downloads fetch it from the configured repository and branch. Existing instruction files are preserved. If Codex is not installed, this step is skipped.

### Codex Terminal Settings (`~/.codex/config.toml`)

During cmux integration, `setup_remote_container_cmux_phase_a.sh` creates `~/.codex/config.toml` if it does not exist, with both the notification command and terminal scrollback enabled. For a root user, the initial file is:

```toml
notify = ["/root/.codex/cmux-notify.sh"]

[tui]
alternate_screen = "never"
```

This preserves terminal scrollback so `Ctrl+a` then `Esc` can browse Codex output in tmux copy mode. The Phase A container script only sets this scrollback default for new files. The native script also adds it to an existing `[tui]` table when the option is absent, preserving explicit values and other TUI settings. Both scripts preserve an existing top-level notification command.

### Codex Prompt Editor

All three remote setup scripts install `~/.local/bin/nvim-prompt-editor`, which runs `nvim -c 'set paste'`. The shared `fish_config.fish` defines a `codex` function when this helper is installed. The function sets `VISUAL` only for the Codex process and its children; the parent shell retains its normal editor setting. Direct `nvim` commands continue to use your usual Neovim configuration.

For a long prompt, press `Ctrl+G` in Codex, enter Insert mode with `i`, paste and edit the text, then press `Esc` and save with `:wq`. Review the returned text in Codex before sending. There is no need to toggle `:set paste` and `:set nopaste` for each paste. Paste mode stays enabled in this editor process, so automatic indentation and Insert-mode mappings are disabled there.

This is a workaround for terminals that do not deliver bracketed-paste markers reliably. If you invoke Codex from Bash, Zsh, or with `command codex`, the Fish function is bypassed. Use the helper explicitly in those cases:

```sh
env VISUAL="$HOME/.local/bin/nvim-prompt-editor" codex
```

After updating an existing machine, open a new Fish shell and restart Codex with `codex resume --last` to use the editor setting. Keep the setup scripts and `fish_config.fish` in sync when copying them to another machine.

### tmux Configuration (`~/.tmux.conf`)

Key settings for OSC 52 clipboard integration:
```bash
set -g allow-passthrough on      # Allow OSC 52 sequences through tmux
set -g set-clipboard external    # Use external clipboard (OSC 52)
```

Plus useful tmux settings:
- Prefix changed to `C-a`
- Vim-like pane navigation (`h/j/k/l`)
- Mouse support enabled
- Vi mode for copy mode
- `Ctrl+a` then `p` uses `paste-buffer -p` to preserve bracketed paste boundaries for multiline prompts

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                    Clipboard Flow                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Remote Neovim (<C-c>)                                      │
│         ↓                                                    │
│  vim.opt.clipboard = "unnamedplus"                          │
│         ↓                                                    │
│  Detects clipboard provider (pbcopy/xclip/tmux)             │
│         ↓                                                    │
│  tmux load-buffer (on remote)                               │
│         ↓                                                    │
│  tmux set-clipboard external → generates OSC 52             │
│         ↓                                                    │
│  OSC 52 escape sequence: \033]52;c;<base64>\007            │
│         ↓                                                    │
│  SSH connection (passes through terminal sequences)         │
│         ↓                                                    │
│  Local Alacritty receives OSC 52                            │
│         ↓                                                    │
│  Alacritty [terminal.osc52 = "CopyPaste"]                  │
│         ↓                                                    │
│  macOS System Clipboard                                     │
│         ↓                                                    │
│  Paste anywhere on macOS with Cmd+V ✓                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Troubleshooting

### Clipboard not working on remote

1. **Check tmux version:**
   ```bash
   tmux -V
   ```
   OSC 52 passthrough (`allow-passthrough`) requires tmux 3.3+

2. **Check Neovim clipboard provider:**
   In Neovim: `:checkhealth provider`

   Should show one of: `tmux`, `xclip`, `xsel`, or `pbcopy`

3. **Verify OSC 52 works at shell level:**
   Inside tmux on remote:
   ```bash
   printf "\033]52;c;%s\a" "$(printf "test_clipboard" | base64)"
   ```
   Then try pasting on macOS. If this doesn't work, the issue is tmux/Alacritty config.

4. **Check if xclip/xsel interfere:**
   If Neovim detects `xclip` or `xsel` on remote, it might use those instead of tmux.
   Either uninstall them or ensure X11 forwarding is enabled: `ssh -X user@remote`

### Still not working?

- Ensure your local Alacritty has the OSC 52 config
- Restart Alacritty completely (Cmd+Q, then reopen)
- On remote, reload tmux config: `tmux source-file ~/.tmux.conf`
- Try killing and restarting tmux session

## Additional Notes

### Using Different Shells

The setup works with any shell (bash, zsh, fish). The clipboard integration is at the tmux/Neovim level, not shell-dependent.

### Multiple Remote Machines

Run this setup script on each remote Linux machine you work with. The configuration is identical across machines.

### Keeping Configs in Sync

Consider using a dotfiles repository to sync:
- `~/.config/nvim/` (Neovim config)
- `~/.tmux.conf` (tmux config)
- `~/.config/fish/` (Fish config, if using)

## Files in This Directory

- `setup_remote_container_cmux_phase_a.sh` - RunPod/Docker setup script for the cmux Phase A workflow
- `claude_settings.json` - Claude Code settings template, copied to `~/.claude/settings.json`
- `AGENTS.md` - Codex Markdown math formatting instructions, copied to `~/.codex/AGENTS.md`
- `setup_remote_linux.sh` - Main setup script for remote machines
- `README.md` - This documentation
- `mac_setup_guide.md` - Guide for local macOS setup (if applicable)

## Native Script Checks

```bash
bash -n mac_dev_setup/setup_remote_linux.sh
shellcheck -S warning mac_dev_setup/setup_remote_linux.sh
python3 -m unittest discover -s mac_dev_setup/tests -v
```

Run these from the repository root. The regression tests use temporary home directories and do not install packages or change login shells. They cover existing credentials/preferences, backups, repeated configuration merges, failed downloads, standalone GitHub URLs, preservation of Neovim data, prompt editing, and the preview bind address. Bash, jq and Python 3.11+ are required; the preview test also requires Node.js and Fish.

## Support

If you encounter issues, check:
1. Alacritty version supports OSC 52 (v0.13.0+)
2. tmux version supports `allow-passthrough` (v3.3+)
3. SSH connection is not dropping escape sequences

---

**Last Updated:** 2026-10-23
