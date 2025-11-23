# Mac Mini Setup Guide - Alacritty + Fish + fzf + ripgrep + tmux + Neovim

Complete guide to replicate your macOS development environment.

---

## Prerequisites

1. **Mac Mini running macOS**
2. **GitHub account access** (for cloning your nvim config)
3. **Internet connection**

---

## Step 1: Install Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

After installation, follow the instructions to add Homebrew to your PATH:

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Verify installation:
```bash
brew --version
```

---

## Step 2: Install Core Tools

```bash
# Terminal emulator
brew install --cask alacritty

# Shell and utilities
brew install fish fzf ripgrep tmux neovim

# Git (if not already installed)
brew install git

# Node.js (required for some Neovim plugins)
brew install node

# Additional useful tools
brew install bat eza fd
```

---

## Step 3: Install Karabiner-Elements (Keyboard Customization)

```bash
brew install --cask karabiner-elements
```

After installation:
1. Open **Karabiner-Elements** from Applications
2. Grant necessary permissions in **System Settings → Privacy & Security**

---

## Step 4: Set Fish as Default Shell

```bash
# Add fish to allowed shells
echo /opt/homebrew/bin/fish | sudo tee -a /etc/shells

# Set fish as default shell
chsh -s /opt/homebrew/bin/fish
```

Log out and log back in, or open a new terminal to activate Fish.

---

## Step 5: Install Fisher (Fish Plugin Manager)

```bash
fish
curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher
```

---

## Step 6: Install Fish Plugins

```bash
# fzf integration
fisher install PatrickF1/fzf.fish

# z (directory jumper)
fisher install jethrokuan/z

# nvm (Node version manager) - if needed
fisher install jorgebucaran/nvm.fish
```

---

## Step 7: Clone Configuration Files from Your MacBook

### Option A: Using Git (Recommended)

If your configs are in a GitHub repo:

```bash
# Neovim config
git clone https://github.com/YOUR_USERNAME/YOUR_NVIM_REPO.git ~/.config/nvim
cd ~/.config/nvim
git checkout newton_stable

# Fish config (if you have a separate repo)
# Or manually copy the files as shown in Option B
```

### Option B: Manual Copy via SSH/rsync

From your **Mac Mini**, run:

```bash
# Create config directories
mkdir -p ~/.config/{alacritty,fish,nvim,karabiner}

# Copy from MacBook (replace MACBOOK_IP with your MacBook's IP)
# You can find IP with: ifconfig | grep "inet " on MacBook

# Alacritty config
scp -r YOUR_USERNAME@MACBOOK_IP:~/.config/alacritty ~/.config/

# Fish config
scp -r YOUR_USERNAME@MACBOOK_IP:~/.config/fish ~/.config/

# Neovim config
scp -r YOUR_USERNAME@MACBOOK_IP:~/.config/nvim ~/.config/

# Karabiner config
scp -r YOUR_USERNAME@MACBOOK_IP:~/.config/karabiner ~/.config/

# Tmux config (if you have one)
scp YOUR_USERNAME@MACBOOK_IP:~/.tmux.conf ~/
```

### Option C: Using iCloud/Dropbox/USB Drive

Copy these directories:
- `~/.config/alacritty/`
- `~/.config/fish/`
- `~/.config/nvim/`
- `~/.config/karabiner/`
- `~/.tmux.conf` (if exists)

---

## Step 8: Setup Neovim

```bash
# Switch to newton_stable branch (if not already)
cd ~/.config/nvim
git checkout newton_stable

# First launch (plugins will auto-install)
nvim

# Wait for all plugins to install
# If you get the rainbow-delimiters error:
rm -rf ~/.local/share/nvim/lazy/rainbow-delimiters.nvim
# Then restart nvim
```

---

## Step 9: Configure Alacritty Themes (if needed)

```bash
cd ~/.config/alacritty
# Clone themes if they're not already in your config
git clone https://github.com/alacritty/alacritty-theme themes
```

---

## Step 10: Setup fzf Key Bindings

Edit `~/.config/fish/config.fish` and ensure it has:

```fish
if status is-interactive
    # fzf key bindings
    source /opt/homebrew/opt/fzf/shell/key-bindings.fish
    fzf_key_bindings

    # Your other configurations...
end
```

Reload Fish config:
```bash
source ~/.config/fish/config.fish
```

---

## Step 11: Verify Karabiner Rules

1. Open **Karabiner-Elements**
2. Go to **Complex Modifications** tab
3. Verify the rule "In iTerm/Alacritty/Terminal: ⌘+C/A/W/R/F/X/Z/S/T/P/H..." is present
4. If missing, the config should already be there from Step 7

---

## Step 12: Setup Codeium (Optional)

```bash
# Launch nvim
nvim

# In nvim, run:
:Codeium Auth

# Follow the authentication flow:
# 1. Open the URL in browser
# 2. Login with your email
# 3. Copy the token
# 4. Paste into nvim
```

---

## Step 13: Install Additional LSPs/Formatters (Optional)

Based on your development needs:

```bash
# Python
brew install black
pip3 install python-lsp-server

# Lua
brew install stylua

# Go
brew install gopls golangci-lint

# Rust
rustup component add rustfmt rust-analyzer

# JavaScript/TypeScript (via npm)
npm install -g typescript typescript-language-server eslint prettier

# Bash
brew install shfmt shellcheck
```

---

## Step 14: Verify Everything Works

### Test Alacritty
```bash
# Launch Alacritty
# Should open with your theme and settings
```

### Test Fish + Git Prompt
```bash
cd ~/.config/nvim
# Should show: "jerry in ~/.config/nvim newton_stable *"
```

### Test fzf
```bash
# Ctrl+R - command history search
# Ctrl+T - file search
# Alt+C - directory search (if enabled)
```

### Test Neovim Keybindings
```bash
nvim
# Try these:
# Cmd+W - close buffer
# Cmd+P - file finder
# Cmd+F - live grep
# Option+M - toggle file tree
```

### Test Karabiner
In Alacritty/Terminal, press:
- `Cmd+W` → should send `Ctrl+W`
- `Cmd+P` → should send `Ctrl+P`
- `Cmd+H` → should send `Ctrl+H`

---

## Step 15: Final Touches

### Set Alacritty as Default Terminal (Optional)

1. Go to **System Settings → Desktop & Dock**
2. Scroll down to **Default web browser** section
3. Set default terminal app

### Git Configuration

```bash
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

### SSH Keys (if needed)

```bash
# Generate new SSH key
ssh-keygen -t ed25519 -C "your.email@example.com"

# Add to ssh-agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Copy public key to clipboard
pbcopy < ~/.ssh/id_ed25519.pub
# Add to GitHub: Settings → SSH and GPG keys
```

---

## Troubleshooting

### Neovim plugins not installing
```bash
# Remove plugin cache
rm -rf ~/.local/share/nvim/lazy

# Restart nvim
nvim
```

### Karabiner not working
1. Check permissions: System Settings → Privacy & Security → Input Monitoring
2. Restart Karabiner-Elements
3. Verify bundle ID: `osascript -e 'id of app "Alacritty"'` should be `org.alacritty`

### Fish prompt not showing git status
```bash
source ~/.config/fish/config.fish
```

### fzf keybindings not working
```bash
# Re-run fzf install
$(brew --prefix)/opt/fzf/install
# Select "yes" for key bindings
```

---

## Quick Checklist

- [ ] Homebrew installed
- [ ] Alacritty installed
- [ ] Fish installed and set as default shell
- [ ] fzf, ripgrep, tmux installed
- [ ] Neovim installed
- [ ] Karabiner-Elements installed
- [ ] All config files copied
- [ ] Neovim plugins installed successfully
- [ ] Fish plugins installed (fisher, fzf.fish, z)
- [ ] Karabiner rules active
- [ ] Git configured
- [ ] Codeium authenticated (optional)
- [ ] LSPs/formatters installed (as needed)

---

## Notes

- **First Neovim launch** will be slow as plugins install
- **Font rendering**: Make sure Nerd Fonts are installed for icons
  ```bash
  brew tap homebrew/cask-fonts
  brew install --cask font-inconsolata-nerd-font
  ```
- **Tmux**: If you have a `.tmux.conf`, copy it to your home directory

---

## Maintenance

### Update everything regularly:

```bash
# Homebrew packages
brew update && brew upgrade

# Neovim plugins
nvim -c "Lazy sync" -c "qa"

# Fish plugins
fisher update
```

---

**Your setup should now be identical on both machines! 🎉**
