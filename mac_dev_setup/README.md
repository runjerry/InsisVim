# Remote Linux Development Setup (tested on Ubuntu24.04)

This directory contains setup scripts for configuring remote Linux machines.

## Scenario

**Local:** macOS with Alacritty terminal
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

### 1. Get the Setup Script on Remote Machine

SSH to your remote Linux machine, then download the setup script:

```bash
# Option 1: Download the script directly
curl -O https://raw.githubusercontent.com/runjerry/InsisVim/remote-setup/mac_dev_setup/setup_remote_container_cmux_phase_a.sh
# or use wget
wget https://raw.githubusercontent.com/runjerry/InsisVim/remote-setup/mac_dev_setup/setup_remote_container_cmux_phase_a.sh

# Option 2: Clone your nvim config repository (if it contains this script)
git clone <your-nvim-config-repo> ~/.config/nvim
```

### 2. Run the Setup Script

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
- Configure Codex's `Ctrl+G` editor to open Neovim in paste mode for multiline prompts
- Guide you through next steps

### 3. Install Tmux and Neovim Plugins

- After starting tmux, press `ctrl+a` then `I` (shift+i) to intall all plugins.
- First launch of nvim will automatically install all plugins.

### 4. Test the Setup

1. Start tmux: `tmux`
2. Open Neovim: `nvim`
3. Check clipboard provider: `:checkhealth provider`
4. Select text in visual mode and press `<C-c>`
5. On your local macOS, press `Cmd+V` to paste

## What Gets Configured

### Claude Code Settings (`~/.claude/settings.json`)

After installing Claude Code, or detecting an existing installation, `setup_remote_container_cmux_phase_a.sh` copies this directory's `claude_settings.json` to `~/.claude/settings.json`. If only the setup script was downloaded, it fetches `claude_settings.json` from the configured GitHub repository and branch. The template does not overwrite an existing `settings.json`. If Claude Code is not installed, this template setup is skipped.

The later cmux integration step adds missing `Stop` and `PostToolUse` (`Task`) notification hooks to `settings.json`, preserving other settings and creating a timestamped backup whenever it changes the file.

### Codex Instructions (`~/.codex/AGENTS.md`)

After installing Codex CLI, or detecting an existing installation, `setup_remote_container_cmux_phase_a.sh` copies this directory's `AGENTS.md` to `~/.codex/AGENTS.md`. If only the setup script was downloaded, it fetches `AGENTS.md` from the configured GitHub repository and branch. Existing `~/.codex/AGENTS.md` files are preserved. If Codex is not installed, this step is skipped.

### Codex Terminal Settings (`~/.codex/config.toml`)

During cmux integration, `setup_remote_container_cmux_phase_a.sh` creates `~/.codex/config.toml` if it does not exist, with both the notification command and terminal scrollback enabled. For a root user, the initial file is:

```toml
notify = ["/root/.codex/cmux-notify.sh"]

[tui]
alternate_screen = "never"
```

This preserves terminal scrollback so `Ctrl+a` then `Esc` can browse Codex output in tmux copy mode. The scrollback default is only set when creating a new file. When the file already exists, setup keeps its TUI settings and only adds a missing top-level notification command.

### Codex Prompt Editor

All three remote setup scripts install `~/.local/bin/codex-prompt-editor`, which runs `nvim -c 'set paste'`. The shared `fish_config.fish` defines a `codex` function when this helper is installed. The function sets `VISUAL` only for the Codex process and its children; the parent shell retains its normal editor setting. Direct `nvim` commands continue to use your usual Neovim configuration.

For a long prompt, press `Ctrl+G` in Codex, enter Insert mode with `i`, paste and edit the text, then press `Esc` and save with `:wq`. Review the returned text in Codex before sending. There is no need to toggle `:set paste` and `:set nopaste` for each paste. Paste mode stays enabled in this editor process, so automatic indentation and Insert-mode mappings are disabled there.

This is a workaround for terminals that do not deliver bracketed-paste markers reliably. If you invoke Codex from Bash, Zsh, or with `command codex`, the Fish function is bypassed. Use the helper explicitly in those cases:

```sh
env VISUAL="$HOME/.local/bin/codex-prompt-editor" codex
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

## Support

If you encounter issues, check:
1. Alacritty version supports OSC 52 (v0.13.0+)
2. tmux version supports `allow-passthrough` (v3.3+)
3. SSH connection is not dropping escape sequences

---

**Last Updated:** 2025-11-23
