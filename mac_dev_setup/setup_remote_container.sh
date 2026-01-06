#!/bin/bash

# RunPod/Docker Container Development Environment Setup Script
# For use with: macOS Alacritty (local) -> SSH -> RunPod/Docker (remote) -> tmux -> neovim
# This script is adapted from setup_remote_linux.sh for container environments
#
# Key differences from setup_remote_linux.sh:
#   - Already running as root (no sudo needed)
#   - No chsh available (use .bashrc to launch fish)
#   - Lightweight checks for missing base packages
#
# Clipboard integration via OSC 52:
#   <C-c> in remote nvim -> paste on local macOS with Cmd+V
#
# Usage:
#   Interactive mode:  ./setup_remote_container.sh
#   Non-interactive:   ./setup_remote_container.sh -y

set -e  # Exit on error

echo "============================================"
echo "RunPod/Docker Development Setup"
echo "============================================"
echo ""

#######################################
# Configuration Variables
#######################################

NVIM_CONFIG_REPO="git@github.com:runjerry/InsisVim.git"
NVIM_CONFIG_BRANCH="remote-setup"  # Change this if you want a different branch
NEOVIM_VERSION="v0.9.5"
AUTO_YES=false

# Parse command line arguments
while getopts "y" opt; do
    case $opt in
        y) AUTO_YES=true ;;
        *) echo "Usage: $0 [-y]"; exit 1 ;;
    esac
done

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
    if [ "$AUTO_YES" = true ]; then
        return 0
    fi
    while true; do
        read -p "$1 (y/n): " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Helper to install a package only if the command is missing
install_if_missing() {
    local cmd="$1"
    local pkg="${2:-$1}"  # Use second arg as package name, or default to command name

    if ! command_exists "$cmd"; then
        print_info "Installing $pkg..."
        $INSTALL_CMD "$pkg"
        print_success "$pkg installed"
    else
        print_success "$cmd already available"
    fi
}

#######################################
# Step 0: Check if running as root
#######################################

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_warning "Not running as root. This script is designed for Docker/RunPod."
        print_info "If you're on a regular Linux machine, consider using setup_remote_linux.sh"
        if ! ask_yes_no "Continue anyway (will use sudo where needed)?"; then
            exit 1
        fi
        USE_SUDO="sudo"
    else
        print_success "Running as root"
        USE_SUDO=""
    fi
}

#######################################
# Step 1: Detect Package Manager
#######################################

detect_package_manager() {
    print_step "Step 1: Detecting Package Manager"

    if command_exists apt-get; then
        PKG_MANAGER="apt-get"
        UPDATE_CMD="$USE_SUDO apt-get update"
        INSTALL_CMD="$USE_SUDO apt-get install -y"
        print_success "Detected: apt-get (Debian/Ubuntu)"
    elif command_exists yum; then
        PKG_MANAGER="yum"
        UPDATE_CMD="$USE_SUDO yum check-update || true"
        INSTALL_CMD="$USE_SUDO yum install -y"
        print_success "Detected: yum (RHEL/CentOS)"
    elif command_exists dnf; then
        PKG_MANAGER="dnf"
        UPDATE_CMD="$USE_SUDO dnf check-update || true"
        INSTALL_CMD="$USE_SUDO dnf install -y"
        print_success "Detected: dnf (Fedora)"
    elif command_exists pacman; then
        PKG_MANAGER="pacman"
        UPDATE_CMD="$USE_SUDO pacman -Sy"
        INSTALL_CMD="$USE_SUDO pacman -S --noconfirm"
        print_success "Detected: pacman (Arch Linux)"
    else
        print_error "No supported package manager found"
        exit 1
    fi
}

#######################################
# Step 2: Install Base Dependencies (if missing)
#######################################

install_base_if_needed() {
    print_step "Step 2: Checking Base Dependencies"

    # Only update package lists if we need to install something
    local need_update=false
    for cmd in curl wget git; do
        if ! command_exists "$cmd"; then
            need_update=true
            break
        fi
    done

    if [ "$need_update" = true ]; then
        print_info "Updating package lists..."
        $UPDATE_CMD
    fi

    # Check and install only missing essentials
    install_if_missing curl
    install_if_missing wget
    install_if_missing git
}

#######################################
# Step 3: Install Core Tools
#######################################

install_core_tools() {
    print_step "Step 3: Installing Core Tools"

    # Fish shell
    if ! command_exists fish; then
        if ask_yes_no "Install Fish shell?"; then
            print_info "Installing fish..."
            if [ "$PKG_MANAGER" = "apt-get" ]; then
                # Try adding PPA for latest fish (may fail in some containers)
                $USE_SUDO add-apt-repository -y ppa:fish-shell/release-3 2>/dev/null || true
                $UPDATE_CMD 2>/dev/null || true
            fi
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

    # unzip (required by Mason to install tools like stylua)
    if ! command_exists unzip; then
        print_info "Installing unzip (required by Mason)..."
        $INSTALL_CMD unzip
        print_success "unzip installed"
    else
        print_success "unzip already installed"
    fi

    # tmux (need 3.3+ for OSC 52 allow-passthrough)
    TMUX_MIN_VERSION="3.3"
    install_tmux_from_source() {
        print_info "Building tmux 3.4 from source..."
        $INSTALL_CMD libevent-dev ncurses-dev build-essential bison pkg-config autoconf automake
        cd /tmp
        wget -q https://github.com/tmux/tmux/releases/download/3.4/tmux-3.4.tar.gz
        tar xzf tmux-3.4.tar.gz
        cd tmux-3.4
        ./configure && make
        $USE_SUDO make install
        cd /tmp && rm -rf tmux-3.4 tmux-3.4.tar.gz
        print_success "tmux 3.4 installed from source"
    }

    if command_exists tmux; then
        TMUX_VERSION=$(tmux -V | sed 's/tmux //')
        # Extract major.minor version for comparison
        TMUX_MAJOR=$(echo "$TMUX_VERSION" | cut -d. -f1)
        TMUX_MINOR=$(echo "$TMUX_VERSION" | cut -d. -f2 | cut -d- -f1 | tr -dc '0-9')

        if [ "$TMUX_MAJOR" -lt 3 ] || ([ "$TMUX_MAJOR" -eq 3 ] && [ "$TMUX_MINOR" -lt 3 ]); then
            print_warning "tmux $TMUX_VERSION is installed, but 3.3+ is required for OSC 52 clipboard"
            if ask_yes_no "Build tmux 3.4 from source?"; then
                install_tmux_from_source
            else
                print_warning "Keeping tmux $TMUX_VERSION - clipboard integration may not work"
            fi
        else
            print_success "tmux already installed: tmux $TMUX_VERSION (>= 3.3, OK)"
        fi
    else
        print_info "Installing tmux..."
        # Try package manager first
        $INSTALL_CMD tmux || true

        if command_exists tmux; then
            TMUX_VERSION=$(tmux -V | sed 's/tmux //')
            TMUX_MAJOR=$(echo "$TMUX_VERSION" | cut -d. -f1)
            TMUX_MINOR=$(echo "$TMUX_VERSION" | cut -d. -f2 | cut -d- -f1 | tr -dc '0-9')

            if [ "$TMUX_MAJOR" -lt 3 ] || ([ "$TMUX_MAJOR" -eq 3 ] && [ "$TMUX_MINOR" -lt 3 ]); then
                print_warning "Package manager installed tmux $TMUX_VERSION, but 3.3+ is required"
                if ask_yes_no "Build tmux 3.4 from source instead?"; then
                    install_tmux_from_source
                fi
            else
                print_success "tmux installed: tmux $TMUX_VERSION"
            fi
        else
            print_warning "Package manager failed to install tmux"
            if ask_yes_no "Build tmux 3.4 from source?"; then
                install_tmux_from_source
            fi
        fi
    fi

    # Node.js (required for some Neovim plugins)
    if ! command_exists node; then
        if ask_yes_no "Install Node.js? (required for some Neovim plugins)"; then
            print_info "Installing Node.js..."
            if [ "$PKG_MANAGER" = "apt-get" ]; then
                # Use NodeSource for newer version
                curl -fsSL https://deb.nodesource.com/setup_lts.x | $USE_SUDO bash -
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
# Step 4: Set Fish as Default Shell
#######################################

setup_fish_shell() {
    print_step "Step 4: Configuring Fish Shell"

    if ! command_exists fish; then
        print_warning "Fish not installed, skipping"
        return
    fi

    # Get fish path
    FISH_PATH=$(which fish)
    print_info "Fish located at: $FISH_PATH"

    # Add fish to allowed shells if not already there
    if [ -f /etc/shells ] && ! grep -q "$FISH_PATH" /etc/shells; then
        print_info "Adding fish to /etc/shells..."
        echo "$FISH_PATH" | $USE_SUDO tee -a /etc/shells > /dev/null
        print_success "Fish added to allowed shells"
    else
        print_success "Fish already in allowed shells"
    fi

    # Try chsh first, fall back to .bashrc if it fails
    if ask_yes_no "Set Fish as your default shell?"; then
        print_info "Trying chsh to set default shell..."
        if $USE_SUDO chsh -s "$FISH_PATH" 2>/dev/null; then
            print_success "Default shell set to Fish via chsh"
        else
            # chsh failed, fall back to .bashrc method
            print_warning "chsh failed, falling back to .bashrc auto-start method"
            if ! grep -q "exec fish" ~/.bashrc 2>/dev/null; then
                print_info "Adding Fish auto-start to .bashrc..."
                cat >> ~/.bashrc << 'EOF'

# Auto-start fish shell (added by setup script)
if command -v fish &> /dev/null && [ -z "$FISH_VERSION" ]; then
    exec fish
fi
EOF
                print_success "Fish will auto-start on login via .bashrc"
            else
                print_success "Fish auto-start already configured in .bashrc"
            fi
        fi
    else
        print_warning "Fish won't be default. Run 'fish' manually or 'exec fish'"
    fi
}

#######################################
# Step 5: Setup Fish Configuration & Plugins
#######################################

setup_fish_config_and_plugins() {
    print_step "Step 5: Setting up Fish Configuration & Plugins"

    if ! command_exists fish; then
        print_warning "Fish not installed, skipping"
        return
    fi

    # Create fish config directory
    mkdir -p ~/.config/fish

    # Download fish config files from GitHub
    local SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

    # Extract repo path from SSH format (git@github.com:user/repo.git -> user/repo)
    local REPO_PATH="${NVIM_CONFIG_REPO#git@github.com:}"
    REPO_PATH="${REPO_PATH%.git}"

    # Check if we're running from the cloned repo
    if [ -f "$SCRIPT_DIR/fish_config.fish" ]; then
        print_info "Copying fish config from local directory..."
        cp "$SCRIPT_DIR/fish_config.fish" ~/.config/fish/config.fish
    else
        # Download from GitHub if not running from repo
        print_info "Downloading fish config from GitHub..."
        curl -fsSL "https://raw.githubusercontent.com/${REPO_PATH}/${NVIM_CONFIG_BRANCH}/mac_dev_setup/fish_config.fish" -o ~/.config/fish/config.fish || {
            print_warning "Failed to download fish config, creating basic config"
            touch ~/.config/fish/config.fish
        }
    fi
    print_success "Fish config.fish in place"

    # Install Fisher (bootstrap) - this overwrites fish_plugins, so we download plugins list AFTER
    print_info "Installing Fisher (Fish plugin manager)..."
    fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher" || true
    print_success "Fisher installed"

    # Now download fish_plugins AFTER Fisher is installed (Fisher overwrites this file)
    if [ -f "$SCRIPT_DIR/fish_plugins" ]; then
        print_info "Copying fish_plugins from local directory..."
        cp "$SCRIPT_DIR/fish_plugins" ~/.config/fish/fish_plugins
    else
        print_info "Downloading fish_plugins from GitHub..."
        curl -fsSL "https://raw.githubusercontent.com/${REPO_PATH}/${NVIM_CONFIG_BRANCH}/mac_dev_setup/fish_plugins" -o ~/.config/fish/fish_plugins || {
            print_warning "Failed to download fish_plugins"
        }
    fi

    # Install all plugins from fish_plugins
    if [ -f ~/.config/fish/fish_plugins ]; then
        print_info "Installing Fish plugins from fish_plugins..."
        fish -c "fisher update" || true
        print_success "Fish plugins installed: fzf.fish, z, npm-global, nvm.fish"
    else
        print_warning "fish_plugins not found, skipping plugin installation"
    fi

    # Add container-specific environment variables to fish config
    if ! grep -q "PIP_BREAK_SYSTEM_PACKAGES" ~/.config/fish/config.fish 2>/dev/null; then
        print_info "Adding container-specific env vars to fish config..."
        cat >> ~/.config/fish/config.fish << 'EOF'

# Allow pip to install system-wide in containers
set -gx PIP_BREAK_SYSTEM_PACKAGES 1
EOF
        print_success "Added PIP_BREAK_SYSTEM_PACKAGES to fish config"
    else
        print_success "PIP_BREAK_SYSTEM_PACKAGES already in fish config"
    fi
}

#######################################
# Step 6: Setup tmux Configuration
#######################################

setup_tmux() {
    print_step "Step 6: Configuring tmux with OSC 52 Support"

    # Backup existing tmux.conf
    if [ -f ~/.tmux.conf ]; then
        print_warning "Backing up existing ~/.tmux.conf to ~/.tmux.conf.backup"
        cp ~/.tmux.conf ~/.tmux.conf.backup.$(date +%Y%m%d_%H%M%S)
    fi

    # Download tmux configuration from GitHub
    local SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

    # Extract repo path from SSH format (git@github.com:user/repo.git -> user/repo)
    local REPO_PATH="${NVIM_CONFIG_REPO#git@github.com:}"
    REPO_PATH="${REPO_PATH%.git}"

    # Check if we're running from the cloned repo
    if [ -f "$SCRIPT_DIR/tmux.conf" ]; then
        print_info "Copying tmux config from local directory..."
        cp "$SCRIPT_DIR/tmux.conf" ~/.tmux.conf
    else
        # Download from GitHub if not running from repo
        print_info "Downloading tmux config from GitHub..."
        curl -fsSL "https://raw.githubusercontent.com/${REPO_PATH}/${NVIM_CONFIG_BRANCH}/mac_dev_setup/tmux.conf" -o ~/.tmux.conf || {
            print_error "Failed to download tmux config"
            return 1
        }
    fi
    print_success "tmux configuration installed at ~/.tmux.conf"

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
# Step 7: Install Neovim
#######################################

install_neovim() {
    print_step "Step 7: Installing Neovim $NEOVIM_VERSION"

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
    $USE_SUDO mkdir -p /usr/local/nvim-${NEOVIM_VERSION}
    $USE_SUDO mv "nvim-${NVIM_ARCH}"/* /usr/local/nvim-${NEOVIM_VERSION}/
    $USE_SUDO ln -sf "/usr/local/nvim-${NEOVIM_VERSION}/bin/nvim" /usr/local/bin/nvim

    # Cleanup
    rm -rf "nvim-${NVIM_ARCH}.tar.gz" "nvim-${NVIM_ARCH}"

    print_success "Neovim $NEOVIM_VERSION installed: $(nvim --version | head -n1)"
}

#######################################
# Step 8: Setup Neovim Configuration
#######################################

setup_neovim_config() {
    print_step "Step 8: Setting up Neovim Configuration"

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
# Step 9: Install Additional Tools
#######################################

install_additional_tools() {
    print_step "Step 9: Installing Additional LSPs/Formatters (Optional)"

    if ! ask_yes_no "Install Python LSP and formatter (python-lsp-server, black)?"; then
        print_warning "Skipping Python tools"
    else
        if command_exists pip3; then
            pip3 install --user python-lsp-server black 2>/dev/null || pip3 install python-lsp-server black
            print_success "Python LSP and black installed"
        elif command_exists pip; then
            pip install --user python-lsp-server black 2>/dev/null || pip install python-lsp-server black
            print_success "Python LSP and black installed"
        else
            print_warning "pip not found, skipping Python tools"
        fi
    fi

    # Claude Code
    if ! command_exists claude; then
        if ask_yes_no "Install Claude Code CLI?"; then
            print_info "Installing Claude Code..."
            curl -fsSL https://claude.ai/install.sh | bash
            # Add ~/.local/bin to fish PATH (where Claude Code is installed)
            if command_exists fish; then
                fish -c "fish_add_path ~/.local/bin" 2>/dev/null || true
                print_success "Claude Code installed and added to fish PATH"
            else
                print_success "Claude Code installed"
                print_warning "Add ~/.local/bin to your PATH manually"
            fi
        else
            print_warning "Skipping Claude Code"
        fi
    else
        print_success "Claude Code already installed"
    fi

    # Add more tools as needed
    print_info "You can install more LSPs later as needed"
}

#######################################
# Main Setup Function
#######################################

main() {
    print_info "This script will set up your RunPod/Docker development environment"
    print_info "It replicates the macOS setup for OSC 52 clipboard integration"
    echo ""

    if [ "$AUTO_YES" = true ]; then
        print_warning "Running in non-interactive mode (-y flag)"
    fi

    if ! ask_yes_no "Continue with setup?"; then
        print_warning "Setup cancelled"
        exit 0
    fi

    check_root
    detect_package_manager
    install_base_if_needed
    install_core_tools
    setup_fish_shell
    setup_fish_config_and_plugins
    setup_tmux
    install_neovim
    setup_neovim_config
    install_additional_tools

    # Print summary
    print_step "Setup Complete!"

    print_success "Your RunPod/Docker environment is now configured!"
    echo ""
    print_info "Next steps:"
    echo "  1. Start a new shell: exec fish (or reconnect)"
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
