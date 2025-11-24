#!/bin/bash

# Remote Linux Development Environment Setup Script
# For use with: macOS Alacritty (local) -> SSH -> Linux (remote) -> tmux -> neovim
# This script replicates the mac_setup_guide.md for remote Linux machines
#
# Clipboard integration via OSC 52:
#   <C-c> in remote nvim → paste on local macOS with Cmd+V

set -e  # Exit on error

echo "=========================================="
echo "Remote Linux Development Setup"
echo "=========================================="
echo ""

#######################################
# Configuration Variables
#######################################

NVIM_CONFIG_REPO="git@github.com:runjerry/InsisVim.git"
NVIM_CONFIG_BRANCH="macos"  # Change this if you want a different branch
NEOVIM_VERSION="v0.9.5"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#######################################
# Helper Functions
#######################################

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC}  $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}→${NC} $1"
}

print_step() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

command_exists() {
    command -v "$1" &> /dev/null
}

ask_yes_no() {
    while true; do
        read -p "$1 (y/n): " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

#######################################
# Step 1: Detect Package Manager
#######################################

detect_package_manager() {
    print_step "Step 1: Detecting Package Manager"

    if command_exists apt-get; then
        PKG_MANAGER="apt-get"
        UPDATE_CMD="sudo apt-get update"
        INSTALL_CMD="sudo apt-get install -y"
        print_success "Detected: apt-get (Debian/Ubuntu)"
    elif command_exists yum; then
        PKG_MANAGER="yum"
        UPDATE_CMD="sudo yum check-update || true"
        INSTALL_CMD="sudo yum install -y"
        print_success "Detected: yum (RHEL/CentOS)"
    elif command_exists dnf; then
        PKG_MANAGER="dnf"
        UPDATE_CMD="sudo dnf check-update || true"
        INSTALL_CMD="sudo dnf install -y"
        print_success "Detected: dnf (Fedora)"
    elif command_exists pacman; then
        PKG_MANAGER="pacman"
        UPDATE_CMD="sudo pacman -Sy"
        INSTALL_CMD="sudo pacman -S --noconfirm"
        print_success "Detected: pacman (Arch Linux)"
    else
        print_error "No supported package manager found"
        exit 1
    fi
}

#######################################
# Step 2: Install Core Tools
#######################################

install_core_tools() {
    print_step "Step 2: Installing Core Tools"

    print_info "Updating package lists..."
    $UPDATE_CMD

    # Git
    if ! command_exists git; then
        print_info "Installing git..."
        $INSTALL_CMD git
        print_success "Git installed"
    else
        print_success "Git already installed: $(git --version)"
    fi

    # Fish shell
    if ! command_exists fish; then
        if ask_yes_no "Install Fish shell?"; then
            print_info "Installing fish..."
            $INSTALL_CMD fish
            print_success "Fish installed"
        else
            print_warning "Skipping Fish installation"
        fi
    else
        print_success "Fish already installed: $(fish --version)"
    fi

    # fzf (install from git for key bindings)
    if ! command_exists fzf; then
        print_info "Installing fzf from git..."
        git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
        ~/.fzf/install --all --no-bash --no-zsh  # Only fish shell
        print_success "fzf installed with key bindings"
    else
        print_success "fzf already installed"
        # Ensure key bindings are installed
        if [ ! -d ~/.fzf ]; then
            print_info "Setting up fzf key bindings..."
            git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
            ~/.fzf/install --all --no-bash --no-zsh
        fi
    fi

    # ripgrep
    if ! command_exists rg; then
        print_info "Installing ripgrep..."
        if [ "$PKG_MANAGER" = "apt-get" ]; then
            $INSTALL_CMD ripgrep
        elif [ "$PKG_MANAGER" = "yum" ] || [ "$PKG_MANAGER" = "dnf" ]; then
            $INSTALL_CMD ripgrep
        elif [ "$PKG_MANAGER" = "pacman" ]; then
            $INSTALL_CMD ripgrep
        fi
        print_success "ripgrep installed"
    else
        print_success "ripgrep already installed"
    fi

    # tmux
    if ! command_exists tmux; then
        print_info "Installing tmux..."
        $INSTALL_CMD tmux
        print_success "tmux installed"
    else
        TMUX_VERSION=$(tmux -V)
        print_success "tmux already installed: $TMUX_VERSION"
    fi

    # Node.js (required for some Neovim plugins)
    if ! command_exists node; then
        if ask_yes_no "Install Node.js? (required for some Neovim plugins)"; then
            print_info "Installing Node.js..."
            if [ "$PKG_MANAGER" = "apt-get" ]; then
                # Use NodeSource for newer version
                curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
                $INSTALL_CMD nodejs
            else
                $INSTALL_CMD nodejs || $INSTALL_CMD node
            fi
            print_success "Node.js installed"
        else
            print_warning "Skipping Node.js installation"
        fi
    else
        print_success "Node.js already installed: $(node --version)"
    fi
}

#######################################
# Step 3: Set Fish as Default Shell
#######################################

setup_fish_shell() {
    print_step "Step 3: Configuring Fish Shell"

    if ! command_exists fish; then
        print_warning "Fish not installed, skipping"
        return
    fi

    # Get fish path
    FISH_PATH=$(which fish)
    print_info "Fish located at: $FISH_PATH"

    # Add fish to allowed shells if not already there
    if ! grep -q "$FISH_PATH" /etc/shells; then
        print_info "Adding fish to /etc/shells..."
        echo "$FISH_PATH" | sudo tee -a /etc/shells
        print_success "Fish added to allowed shells"
    else
        print_success "Fish already in allowed shells"
    fi

    # Change default shell
    if [ "$SHELL" != "$FISH_PATH" ]; then
        if ask_yes_no "Set Fish as your default shell?"; then
            sudo chsh -s "$FISH_PATH" "$USER"
            print_success "Default shell set to Fish (will take effect on next login)"
        else
            print_warning "Keeping current shell: $SHELL"
        fi
    else
        print_success "Fish is already your default shell"
    fi
}

#######################################
# Step 4: Setup Fish Configuration & Plugins
#######################################

setup_fish_config_and_plugins() {
    print_step "Step 4: Setting up Fish Configuration & Plugins"

    if ! command_exists fish; then
        print_warning "Fish not installed, skipping"
        return
    fi

    # Create fish config directory
    mkdir -p ~/.config/fish

    # Download fish config files from GitHub
    local SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

    # Check if we're running from the cloned repo
    if [ -f "$SCRIPT_DIR/fish_config.fish" ] && [ -f "$SCRIPT_DIR/fish_plugins" ]; then
        print_info "Copying fish config files from local directory..."
        cp "$SCRIPT_DIR/fish_config.fish" ~/.config/fish/config.fish
        cp "$SCRIPT_DIR/fish_plugins" ~/.config/fish/fish_plugins
    else
        # Download from GitHub if not running from repo
        print_info "Downloading fish config files from GitHub..."
        curl -fsSL "https://raw.githubusercontent.com/${NVIM_CONFIG_REPO#*github.com/}/remote-setup/mac_dev_setup/fish_config.fish" -o ~/.config/fish/config.fish || {
            print_warning "Failed to download fish config, creating basic config"
            touch ~/.config/fish/config.fish
        }
        curl -fsSL "https://raw.githubusercontent.com/${NVIM_CONFIG_REPO#*github.com/}/remote-setup/mac_dev_setup/fish_plugins" -o ~/.config/fish/fish_plugins || {
            print_warning "Failed to download fish_plugins"
        }
    fi
    print_success "Fish config files in place"

    # Install Fisher (bootstrap)
    print_info "Installing Fisher (Fish plugin manager)..."
    fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher" || true
    print_success "Fisher installed"

    # Install all plugins from fish_plugins
    if [ -f ~/.config/fish/fish_plugins ]; then
        print_info "Installing Fish plugins from fish_plugins..."
        fish -c "fisher update" || true
        print_success "Fish plugins installed: fzf.fish, z, npm-global, nvm.fish"
    else
        print_warning "fish_plugins not found, skipping plugin installation"
    fi
}

#######################################
# Step 5: Setup tmux Configuration
#######################################

setup_tmux() {
    print_step "Step 5: Configuring tmux with OSC 52 Support"

    # Backup existing tmux.conf
    if [ -f ~/.tmux.conf ]; then
        print_warning "Backing up existing ~/.tmux.conf to ~/.tmux.conf.backup"
        cp ~/.tmux.conf ~/.tmux.conf.backup.$(date +%Y%m%d_%H%M%S)
    fi

    # Create tmux configuration
    cat > ~/.tmux.conf << 'TMUX_EOF'
# Tmux configuration for remote development with OSC 52 clipboard support

set -g default-terminal "tmux-256color"
# Enable true-color support
set -ag terminal-overrides ",xterm-256color:RGB"

# Allow passthrough for OSC 52 (tmux 3.3+)
set -g allow-passthrough on

# Use external clipboard (enables OSC 52 passthrough)
set -g set-clipboard external

# remap prefix from 'C-b' to 'C-a'
set -g prefix C-a
unbind C-b
bind-key C-a send-prefix

# Split panes using \ and -
unbind %
bind '\' split-window -h
unbind '"'
bind - split-window -v

# Reload configuration
unbind r
bind r source-file ~/.tmux.conf \; display-message "Config reloaded!"

# Moving between panes
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# Re-bind last window command
bind b last-window

# Pane resizing
bind -r H resize-pane -L 5
bind -r J resize-pane -D 5
bind -r K resize-pane -U 5
bind -r L resize-pane -R 5

# Enable mouse support
set -g mouse on

# Set vi mode for copy mode
set-window-option -g mode-keys vi

# Copy mode bindings
bind Escape copy-mode
unbind p
bind p paste-buffer
bind-key -T copy-mode-vi 'v' send -X begin-selection
bind-key -T copy-mode-vi 'y' send -X copy-selection
unbind -T copy-mode-vi MouseDragEnd1Pane

# Remove delay for exiting insert mode with ESC in Neovim
set -sg escape-time 10

# Rather than constraining window size to the maximum size of any client
# connected to the *session*, constrain window size to the maximum size of any
# client connected to *that window*
setw -g aggressive-resize on

# always display tabline
set -g showtabline 2

# Status bar configuration
set -g status-position bottom
set -g status-justify left
set -g status-style 'bg=colour234 fg=colour137'
set -g status-left ''
set -g status-right '#[fg=colour233,bg=colour241,bold] %d/%m #[fg=colour233,bg=colour245,bold] %H:%M:%S '
set -g status-right-length 50
set -g status-left-length 20

# Window status
setw -g window-status-current-style 'fg=colour1 bg=colour19 bold'
setw -g window-status-current-format ' #I#[fg=colour249]:#[fg=colour255]#W#[fg=colour249]#F '
setw -g window-status-style 'fg=colour9 bg=colour18'
setw -g window-status-format ' #I#[fg=colour237]:#[fg=colour250]#W#[fg=colour244]#F '

# Pane borders
set -g pane-border-style 'fg=colour238'
set -g pane-active-border-style 'fg=colour51'

# Messages
set -g message-style 'fg=colour232 bg=colour166 bold'

# tmux plugin manager
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'christoomey/vim-tmux-navigator'
set -g @plugin 'tmux-plugins/tmux-continuum'

set -g @continuum-restore 'on'

# Initialize TMUX plugin manager (keep this line at the very bottom of tmux.conf)
run '~/.tmux/plugins/tpm/tpm'
TMUX_EOF

    print_success "tmux configuration created at ~/.tmux.conf"

    # Install TPM (Tmux Plugin Manager)
    if [ ! -d ~/.tmux/plugins/tpm ]; then
        print_info "Installing Tmux Plugin Manager (TPM)..."
        git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
        print_success "TPM installed"
        print_warning "After starting tmux, press 'Ctrl+a' then 'I' (capital i) to install plugins"
    else
        print_success "TPM already installed"
    fi
}

#######################################
# Step 6: Install Neovim
#######################################

install_neovim() {
    print_step "Step 6: Installing Neovim $NEOVIM_VERSION"

    if command_exists nvim; then
        CURRENT_VERSION=$(nvim --version | head -n1)
        print_success "Neovim already installed: $CURRENT_VERSION"
        if ! ask_yes_no "Reinstall Neovim $NEOVIM_VERSION?"; then
            return
        fi
    fi

    # Detect architecture
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        NVIM_ARCH="linux64"
    elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
        NVIM_ARCH="linux64"  # Neovim uses same binary
    else
        print_error "Unsupported architecture: $ARCH"
        return
    fi

    print_info "Downloading Neovim $NEOVIM_VERSION for $ARCH..."
    cd /tmp
    wget -q "https://github.com/neovim/neovim/releases/download/${NEOVIM_VERSION}/nvim-${NVIM_ARCH}.tar.gz"

    print_info "Extracting Neovim..."
    tar xzf "nvim-${NVIM_ARCH}.tar.gz"

    print_info "Installing Neovim to /usr/local..."
    sudo mkdir -p /usr/local/nvim-${NEOVIM_VERSION}
    sudo mv "nvim-${NVIM_ARCH}"/* /usr/local/nvim-${NEOVIM_VERSION}/
    sudo ln -sf "/usr/local/nvim-${NEOVIM_VERSION}/bin/nvim" /usr/local/bin/nvim

    # Cleanup
    rm -rf "nvim-${NVIM_ARCH}.tar.gz" "nvim-${NVIM_ARCH}"

    print_success "Neovim $NEOVIM_VERSION installed: $(nvim --version | head -n1)"
}

#######################################
# Step 7: Setup Neovim Configuration
#######################################

setup_neovim_config() {
    print_step "Step 7: Setting up Neovim Configuration"

    # Clean up existing nvim configs if requested
    if [ -d ~/.config/nvim ] || [ -d ~/.local/share/nvim ] || [ -d ~/.cache/nvim ]; then
        print_warning "Existing Neovim configuration detected"
        if ask_yes_no "Remove existing Neovim configs and start fresh?"; then
            print_info "Removing existing Neovim data..."
            rm -rf ~/.local/share/nvim
            rm -rf ~/.cache/nvim
            rm -rf ~/.config/nvim
            print_success "Existing configs removed"
        fi
    fi

    # Clone nvim config repository
    if [ ! -d ~/.config/nvim ]; then
        print_info "Cloning Neovim config from $NVIM_CONFIG_REPO..."
        git clone "$NVIM_CONFIG_REPO" ~/.config/nvim
        cd ~/.config/nvim
        git checkout "$NVIM_CONFIG_BRANCH"
        print_success "Neovim config cloned (branch: $NVIM_CONFIG_BRANCH)"
    else
        print_success "~/.config/nvim already exists"
        cd ~/.config/nvim
        print_info "Current branch: $(git branch --show-current)"
    fi

    print_warning "First launch of Neovim will install plugins automatically"
    print_info "This may take a few minutes..."
}

#######################################
# Step 8: Install Additional Tools
#######################################

install_additional_tools() {
    print_step "Step 8: Installing Additional LSPs/Formatters (Optional)"

    if ! ask_yes_no "Install Python LSP and formatter (python-lsp-server, black)?"; then
        print_warning "Skipping Python tools"
    else
        if command_exists pip3; then
            pip3 install --user python-lsp-server black
            print_success "Python LSP and black installed"
        else
            print_warning "pip3 not found, skipping Python tools"
        fi
    fi

    # Add more tools as needed
    print_info "You can install more LSPs later as needed"
}

#######################################
# Main Setup Function
#######################################

main() {
    print_info "This script will set up your remote Linux development environment"
    print_info "It replicates the macOS setup for OSC 52 clipboard integration"
    echo ""

    if ! ask_yes_no "Continue with setup?"; then
        print_warning "Setup cancelled"
        exit 0
    fi

    detect_package_manager
    install_core_tools
    setup_fish_shell
    setup_fish_config_and_plugins
    setup_tmux
    install_neovim
    setup_neovim_config
    install_additional_tools

    # Print summary
    print_step "Setup Complete! 🎉"

    print_success "Your remote Linux machine is now configured!"
    echo ""
    print_info "Next steps:"
    echo "  1. Log out and log back in (or run: exec fish)"
    echo "  2. Start tmux: tmux"
    echo "  3. Install tmux plugins: Press Ctrl+a then Shift+I"
    echo "  4. Start neovim: nvim"
    echo "  5. Wait for plugins to install"
    echo "  6. In nvim, run: :checkhealth provider"
    echo ""
    print_info "Test clipboard integration:"
    echo "  - In nvim, select text and press <C-c>"
    echo "  - On your local macOS, press Cmd+V to paste"
    echo ""
    print_warning "Make sure your local Alacritty has:"
    echo "  [terminal]"
    echo "  osc52 = \"CopyPaste\""
    echo ""
    print_success "Happy coding!"
}

# Run main function
main
