#!/bin/bash

# RunPod/Docker Container Development Environment Setup Script
# For use with: macOS cmux/Ghostty (local) -> cmux ssh -> RunPod/Docker (remote) -> tmux -> neovim/agents
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
#   Interactive mode:  ./setup_remote_container_cmux_phase_a.sh
#   Non-interactive:   ./setup_remote_container_cmux_phase_a.sh -y

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
NEOVIM_LINUX64_SHA256="44ee395d9b5f8a14be8ec00d3b8ead34e18fe6461e40c9c8c50e6956d643b6ca"
TMUX_SOURCE_SHA256="551ab8dea0bf505c0ad6b7bb35ef567cdde0ccb84357df142c254f35a23e19aa"
MDPREV_VERSION="0.1.1"
AUTO_YES=false
SETUP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Make user-local tools installed by the baseline setup visible immediately in
# this run; Fish persists the same paths for future sessions.
export PATH="$HOME/.local/bin:$HOME/.node_modules/bin:$PATH"

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
        INSTALL_CMD="$USE_SUDO apt-get install -y"
        print_success "Detected: apt-get (Debian/Ubuntu)"
    elif command_exists yum; then
        PKG_MANAGER="yum"
        INSTALL_CMD="$USE_SUDO yum install -y"
        print_success "Detected: yum (RHEL/CentOS)"
    elif command_exists dnf; then
        PKG_MANAGER="dnf"
        INSTALL_CMD="$USE_SUDO dnf install -y"
        print_success "Detected: dnf (Fedora)"
    elif command_exists pacman; then
        PKG_MANAGER="pacman"
        INSTALL_CMD="$USE_SUDO pacman -S --noconfirm"
        print_success "Detected: pacman (Arch Linux)"
    else
        print_error "No supported package manager found"
        exit 1
    fi
}

update_package_lists() {
    local status=0

    case "$PKG_MANAGER" in
        apt-get)
            $USE_SUDO apt-get update
            ;;
        yum)
            $USE_SUDO yum check-update || status=$?
            [ "$status" -eq 0 ] || [ "$status" -eq 100 ]
            ;;
        dnf)
            $USE_SUDO dnf check-update || status=$?
            [ "$status" -eq 0 ] || [ "$status" -eq 100 ]
            ;;
        pacman)
            $USE_SUDO pacman -Sy
            ;;
    esac
}

#######################################
# Step 2: Install Base Dependencies (if missing)
#######################################

install_base_if_needed() {
    print_step "Step 2: Checking Base Dependencies"

    # Update package lists if any base dependency is missing
    local need_update=false
    for cmd in curl wget git less jq ss ps realpath nohup cmp sha256sum tar gzip make cc; do
        if ! command_exists "$cmd"; then
            need_update=true
            break
        fi
    done

    if [ "$need_update" = true ]; then
        print_info "Updating package lists..."
        update_package_lists
    fi

    # Check and install only missing essentials
    install_if_missing curl
    install_if_missing wget
    install_if_missing git
    install_if_missing less  # Required for git pager (git log, git diff, etc.)
    install_if_missing jq    # Required by Claude/Codex cmux notification bridges

    case "$PKG_MANAGER" in
        apt-get)
            install_if_missing ss iproute2
            install_if_missing ps procps
            install_if_missing realpath coreutils
            install_if_missing nohup coreutils
            install_if_missing cmp diffutils
            install_if_missing sha256sum coreutils
            install_if_missing tar tar
            install_if_missing gzip gzip
            install_if_missing make build-essential
            install_if_missing cc build-essential
            ;;
        yum|dnf)
            install_if_missing ss iproute
            install_if_missing ps procps-ng
            install_if_missing realpath coreutils
            install_if_missing nohup coreutils
            install_if_missing cmp diffutils
            install_if_missing sha256sum coreutils
            install_if_missing tar tar
            install_if_missing gzip gzip
            install_if_missing make make
            install_if_missing cc gcc
            ;;
        pacman)
            install_if_missing ss iproute2
            install_if_missing ps procps-ng
            install_if_missing realpath coreutils
            install_if_missing nohup coreutils
            install_if_missing cmp diffutils
            install_if_missing sha256sum coreutils
            install_if_missing tar tar
            install_if_missing gzip gzip
            install_if_missing make base-devel
            install_if_missing cc base-devel
            ;;
    esac

    # Configure git user identity
    print_info "Configuring git user identity..."
    git config --global user.email "qinxun@gmail.com"
    git config --global user.name "Jerry Bai"
    print_success "Git configured: Jerry Bai <qinxun@gmail.com>"
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
                update_package_lists 2>/dev/null || true
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
    install_tmux_from_source() {
        local build_dir
        local archive

        print_info "Building tmux 3.4 from source..."
        case "$PKG_MANAGER" in
            apt-get)
                $INSTALL_CMD libevent-dev ncurses-dev build-essential bison pkg-config autoconf automake
                ;;
            yum|dnf)
                $INSTALL_CMD libevent-devel ncurses-devel gcc make bison pkgconf-pkg-config autoconf automake
                ;;
            pacman)
                $INSTALL_CMD libevent ncurses base-devel bison pkgconf autoconf automake
                ;;
        esac
        build_dir="$(mktemp -d)"
        archive="$build_dir/tmux-3.4.tar.gz"
        wget -q -O "$archive" https://github.com/tmux/tmux/releases/download/3.4/tmux-3.4.tar.gz
        if ! printf '%s  %s\n' "$TMUX_SOURCE_SHA256" "$archive" | sha256sum -c -; then
            rm -rf "$build_dir"
            print_error "tmux source archive checksum verification failed"
            return 1
        fi
        tar xzf "$archive" -C "$build_dir"
        if ! (
            cd "$build_dir/tmux-3.4" &&
            ./configure &&
            make &&
            $USE_SUDO make install
        ); then
            rm -rf "$build_dir"
            print_error "tmux source build failed"
            return 1
        fi
        rm -rf "$build_dir"
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
                local node_setup
                node_setup="$(mktemp)"
                if ! curl -fsSL https://deb.nodesource.com/setup_lts.x -o "$node_setup" ||
                   ! $USE_SUDO bash "$node_setup"; then
                    rm -f "$node_setup"
                    print_error "NodeSource setup failed"
                    return 1
                fi
                rm -f "$node_setup"
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

    # npm/npx are required by Codex and the Markdown reviewer. Some distro
    # Node packages do not include them.
    if command_exists node; then
        if ! command_exists npm || ! command_exists npx; then
            print_info "Installing npm/npx..."
            $INSTALL_CMD npm
        fi

        if command_exists npm && command_exists npx; then
            print_success "npm/npx available: npm $(npm --version), npx $(npx --version)"
        else
            print_error "npm/npx are required but unavailable"
            return 1
        fi
    else
        print_warning "Node.js was skipped; Codex and Markdown preview setup will also be skipped"
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

    local fish_path
    local current_login_shell
    local user_name
    local bashrc_marker="# cmux-phase-a-v3: defer interactive Bash to Fish"

    fish_path="$(command -v fish)"
    user_name="$(id -un)"
    current_login_shell="$(getent passwd "$user_name" 2>/dev/null | awk -F: '{print $7}')"

    print_info "Fish located at: $fish_path"

    # Add fish to allowed shells if not already there
    if [ -f /etc/shells ] && ! grep -Fxq "$fish_path" /etc/shells; then
        print_info "Adding fish to /etc/shells..."
        echo "$fish_path" | $USE_SUDO tee -a /etc/shells > /dev/null
        print_success "Fish added to allowed shells"
    else
        print_success "Fish already in allowed shells"
    fi

    # Configure both the account login shell and a guarded Bash handoff. Some
    # container SSH entrypoints ignore /etc/passwd and explicitly launch Bash;
    # the handoff makes those interactive sessions enter Fish as well.
    if ask_yes_no "Set Fish as your default shell?"; then
        if [ "$current_login_shell" = "$fish_path" ]; then
            print_success "Fish is already the account login shell"
        elif command_exists chsh && $USE_SUDO chsh -s "$fish_path" "$user_name" 2>/dev/null; then
            print_success "Account login shell set to Fish"
        else
            print_warning "Could not change the account login shell; using the Bash handoff"
        fi

        if ! grep -Fq "$bashrc_marker" "$HOME/.bashrc" 2>/dev/null; then
            print_info "Adding guarded interactive-Bash to Fish handoff..."
            cat >> "$HOME/.bashrc" << 'EOF'

# cmux-phase-a-v3: defer interactive Bash to Fish
# cmux's generated .bashrc loads this user file before exporting its CMUX_*
# variables. Defer the handoff until the first prompt, after cmux has finished
# installing its own PROMPT_COMMAND and environment.
if [[ $- == *i* ]] && command -v fish >/dev/null 2>&1 && [ -z "${FISH_VERSION:-}" ]; then
    _cmux_phase_a_enter_fish() {
        # cmux ssh generates a per-workspace Fish config that reports PWD,
        # shell activity, ports and TTY state. Launch Fish through it while
        # retaining the user's real Fish config directory.
        if [ -n "${CMUX_SHELL_INTEGRATION_DIR:-}" ] &&
           [ -r "$CMUX_SHELL_INTEGRATION_DIR/fish/config.fish" ]; then
            if [ "${XDG_CONFIG_HOME:-}" != "$CMUX_SHELL_INTEGRATION_DIR" ]; then
                export CMUX_FISH_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
                export XDG_CONFIG_HOME="$CMUX_SHELL_INTEGRATION_DIR"
            fi
        fi
        exec fish
    }

    case ";${PROMPT_COMMAND:-};" in
        *';_cmux_phase_a_enter_fish;'*) ;;
        *) PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_cmux_phase_a_enter_fish" ;;
    esac
fi
EOF
            print_success "Interactive Bash sessions will hand off to Fish"
        else
            print_success "Interactive Bash-to-Fish handoff already configured"
        fi

        print_warning "The current parent shell cannot be replaced by a child setup script"
        print_info "Run 'exec fish' now, or reconnect through cmux before starting tmux"
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

    # cmux installs its relay and a per-workspace Fish integration on
    # `cmux ssh`. The integration reports PWD so the Files surface follows
    # navigation in the outer Fish shell. Load it additively when Fish was
    # started normally rather than through cmux's injected XDG config.
    mkdir -p ~/.config/fish/conf.d
    local cmux_fish="$HOME/.config/fish/conf.d/99-cmux.fish"

    if [ ! -e "$cmux_fish" ]; then
        cat > "$cmux_fish" << 'EOF'
# cmux remote integration (installed automatically by `cmux ssh`)
fish_add_path $HOME/.cmux/bin
EOF
    fi

    if ! grep -Eq 'fish_add_path.*\.cmux/bin' "$cmux_fish" 2>/dev/null; then
        printf '\nfish_add_path $HOME/.cmux/bin\n' >> "$cmux_fish"
    fi

    if ! grep -Fq '# cmux-phase-a-shell-integration-v2' "$cmux_fish" 2>/dev/null; then
        cat >> "$cmux_fish" << 'EOF'

# cmux-phase-a-shell-integration-v2
# A normal `exec fish` bypasses cmux's injected Fish config. Source that
# integration after marking the user's config as already loaded, preventing
# it from recursively sourcing this file/config.fish again.
if set -q CMUX_SHELL_INTEGRATION_DIR
    set -l _cmux_fish_integration "$CMUX_SHELL_INTEGRATION_DIR/fish/config.fish"
    if test -r "$_cmux_fish_integration"; and not functions -q _cmux_prompt
        set -g CMUX_FISH_USER_CONFIG_ALREADY_LOADED 1
        source "$_cmux_fish_integration"
        set -e CMUX_FISH_USER_CONFIG_ALREADY_LOADED
    end
    set -e _cmux_fish_integration
end
EOF
    fi

    chmod 644 "$cmux_fish"
    print_success "cmux relay PATH and Fish PWD reporting configured"
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

    # Make new tmux panes deterministic even if the outer container shell or
    # SSH entrypoint supplied an outdated SHELL value.
    if command_exists fish && ! grep -Eq '^(set|set-option)[[:space:]]+-g[[:space:]]+default-shell[[:space:]]' ~/.tmux.conf 2>/dev/null; then
        printf '\n# Use Fish for new tmux panes (added by container setup)\n' >> ~/.tmux.conf
        printf 'set-option -g default-shell "%s"\n' "$(command -v fish)" >> ~/.tmux.conf
        print_success "tmux default shell set to Fish for new servers/panes"
    fi

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
        print_error "Neovim $NEOVIM_VERSION does not provide this x86_64 archive for $ARCH"
        return 1
    else
        print_error "Unsupported architecture: $ARCH"
        return
    fi

    print_info "Downloading Neovim $NEOVIM_VERSION for $ARCH..."
    local tmp_dir
    local archive
    local extracted

    tmp_dir="$(mktemp -d)"
    archive="$tmp_dir/nvim-${NVIM_ARCH}.tar.gz"
    extracted="$tmp_dir/nvim-${NVIM_ARCH}"
    wget -q -O "$archive" \
        "https://github.com/neovim/neovim/releases/download/${NEOVIM_VERSION}/nvim-${NVIM_ARCH}.tar.gz"

    if ! printf '%s  %s\n' "$NEOVIM_LINUX64_SHA256" "$archive" | sha256sum -c -; then
        rm -rf "$tmp_dir"
        print_error "Neovim archive checksum verification failed"
        return 1
    fi

    print_info "Extracting Neovim..."
    tar xzf "$archive" -C "$tmp_dir"

    print_info "Installing Neovim to /usr/local..."
    $USE_SUDO mkdir -p /usr/local/nvim-${NEOVIM_VERSION}
    $USE_SUDO cp -a "$extracted"/. /usr/local/nvim-${NEOVIM_VERSION}/
    $USE_SUDO ln -sf "/usr/local/nvim-${NEOVIM_VERSION}/bin/nvim" /usr/local/bin/nvim

    # Cleanup
    rm -rf "$tmp_dir"

    print_success "Neovim $NEOVIM_VERSION installed: $(nvim --version | head -n1)"
}

#######################################
# Step 8: Setup Neovim Configuration
#######################################

setup_neovim_config() {
    print_step "Step 8: Setting up Neovim Configuration"

    local config_dir="$HOME/.config/nvim"
    local repo_path="${NVIM_CONFIG_REPO#git@github.com:}"
    local https_repo

    repo_path="${repo_path%.git}"
    https_repo="https://github.com/${repo_path}.git"

    # The setup script is intended to be committed inside this repository.
    # Never delete the checkout containing the script currently being read.
    case "$SETUP_SCRIPT_DIR/" in
        "$config_dir/"*)
            print_success "Running from the Neovim config checkout; preserving it"
            return 0
            ;;
    esac

    # Clean up existing nvim configs if requested
    if [ -d "$config_dir" ] || [ -d ~/.local/share/nvim ] || [ -d ~/.cache/nvim ]; then
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
    if [ ! -d "$config_dir" ]; then
        print_info "Cloning Neovim config branch $NVIM_CONFIG_BRANCH..."
        if ! git clone --branch "$NVIM_CONFIG_BRANCH" --single-branch "$https_repo" "$config_dir"; then
            rm -rf "$config_dir"
            print_warning "HTTPS clone failed; retrying with $NVIM_CONFIG_REPO"
            git clone --branch "$NVIM_CONFIG_BRANCH" --single-branch "$NVIM_CONFIG_REPO" "$config_dir"
        fi
        print_success "Neovim config cloned (branch: $NVIM_CONFIG_BRANCH)"
    else
        print_success "~/.config/nvim already exists"
        if [ -d "$config_dir/.git" ]; then
            print_info "Current branch: $(git -C "$config_dir" branch --show-current)"
        fi
    fi

}

install_neovim_plugins() {
    print_step "Step 8b: Installing Neovim Plugins"

    local config_dir="$HOME/.config/nvim"
    local lock_file="$config_dir/lazy-lock.json"
    local lazy_root="$HOME/.local/share/nvim/lazy"
    local missing_count=0
    local plugin
    local verify_command

    if ! command_exists nvim; then
        print_error "Neovim is unavailable; cannot install plugins"
        return 1
    fi

    if [ ! -f "$config_dir/lua/insis/lazy.lua" ]; then
        print_warning "InsisVim Lazy configuration not found; skipping managed plugin bootstrap"
        return 0
    fi

    if ! jq -e 'type == "object"' "$lock_file" >/dev/null 2>&1; then
        print_error "Missing or invalid plugin lock file: $lock_file"
        return 1
    fi

    while IFS= read -r plugin; do
        [ -d "$lazy_root/$plugin" ] || missing_count=$((missing_count + 1))
    done < <(jq -r 'keys[]' "$lock_file")

    if [ "$missing_count" -eq 0 ]; then
        print_success "All lockfile plugin directories are already present"
        return 0
    fi

    print_info "First-run bootstrap: installing missing plugins (this can take several minutes)..."
    verify_command='lua local missing = {}; for name, plugin_spec in pairs(require("lazy.core.config").plugins) do if plugin_spec.url and not plugin_spec._.installed then missing[#missing + 1] = name end end; if #missing > 0 then vim.api.nvim_err_writeln("Missing Lazy plugins: " .. table.concat(missing, ", ")); vim.cmd("cquit 1") end'

    if ! GIT_TERMINAL_PROMPT=0 nvim --headless \
        "+Lazy! install" \
        "+$verify_command" \
        +qa; then
        print_error "Neovim plugin bootstrap failed"
        print_info "Retry with: nvim --headless '+Lazy! install' +qa"
        return 1
    fi

    if [ ! -d "$lazy_root/lazy.nvim" ]; then
        print_error "lazy.nvim was not installed"
        return 1
    fi

    print_success "All enabled Neovim plugins are installed"
}

#######################################
# Step 9: Install Additional Tools
#######################################

setup_claude_settings() {
    local target="$HOME/.claude/settings.json"

    if [ -f "$target" ]; then
        print_success "Claude settings already exist, leaving unchanged"
        return
    fi

    mkdir -p "$HOME/.claude"

    if [ -f "$SETUP_SCRIPT_DIR/claude_settings.json" ]; then
        print_info "Copying Claude settings from local directory..."
        install -m 600 "$SETUP_SCRIPT_DIR/claude_settings.json" "$target"
    else
        local repo_path="${NVIM_CONFIG_REPO#git@github.com:}"
        repo_path="${repo_path%.git}"

        local tmp_file
        tmp_file="$(mktemp)"

        print_info "Downloading Claude settings from GitHub..."
        if curl -fsSL \
            "https://raw.githubusercontent.com/${repo_path}/${NVIM_CONFIG_BRANCH}/mac_dev_setup/claude_settings.json" \
            -o "$tmp_file"; then
            if ! install -m 600 "$tmp_file" "$target"; then
                rm -f "$tmp_file"
                print_error "Failed to install Claude settings"
                return 1
            fi
        else
            print_warning "Failed to download Claude settings"
        fi

        rm -f "$tmp_file"
    fi

    if [ -f "$target" ]; then
        print_success "Claude settings installed at $target"
    fi
}

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
            local claude_installer
            claude_installer="$(mktemp)"
            if ! curl -fsSL https://claude.ai/install.sh -o "$claude_installer" ||
               ! bash "$claude_installer"; then
                rm -f "$claude_installer"
                print_error "Claude Code installer failed"
                return 1
            fi
            rm -f "$claude_installer"
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

    if command_exists claude || [ -x "$HOME/.local/bin/claude" ]; then
        setup_claude_settings
    fi

    # Codex CLI
    if ! command_exists codex; then
        if ask_yes_no "Install OpenAI Codex CLI?"; then
            if command_exists npm; then
                print_info "Installing Codex CLI..."
                npm install -g --prefix "$HOME/.node_modules" @openai/codex
                export PATH="$HOME/.node_modules/bin:$PATH"
                print_success "Codex CLI installed"
            else
                print_warning "npm not found, skipping Codex CLI installation"
            fi
        else
            print_warning "Skipping Codex CLI"
        fi
    else
        print_success "Codex CLI already installed: $(codex --version 2>/dev/null || true)"
    fi

    # Add more tools as needed
    print_info "You can install more LSPs later as needed"
}

#######################################
# Step 10: Configure cmux Phase A Remote Integration
#######################################

setup_cmux_claude_notifications() {
    local settings="$HOME/.claude/settings.json"
    local hook_dir="$HOME/.claude/hooks"
    local hook_script="$hook_dir/cmux-notify.sh"
    local tmp_file

    if ! command_exists jq; then
        print_warning "jq is required for Claude cmux notifications; skipping"
        return 0
    fi

    mkdir -p "$hook_dir"

    if [ ! -e "$hook_script" ]; then
        cat > "$hook_script" << 'EOF'
#!/usr/bin/env bash

CMUX="$HOME/.cmux/bin/cmux"

# The remote relay exists only inside a cmux-managed SSH workspace.
[ -x "$CMUX" ] || exit 0
"$CMUX" ping >/dev/null 2>&1 || exit 0

EVENT="$(cat)"
EVENT_TYPE="$(printf '%s' "$EVENT" | jq -r '.hook_event_name // "unknown"')"
TOOL="$(printf '%s' "$EVENT" | jq -r '.tool_name // ""')"

case "$EVENT_TYPE" in
    Stop)
        "$CMUX" notify \
            --title "Claude Code" \
            --subtitle "Done" \
            --body "Session complete"
        ;;

    PostToolUse)
        if [ "$TOOL" = "Task" ]; then
            "$CMUX" notify \
                --title "Claude Code" \
                --subtitle "Agent" \
                --body "Subagent finished"
        fi
        ;;
esac

exit 0
EOF
        chmod 700 "$hook_script"
        print_success "Claude cmux notifier installed"
    else
        print_success "Existing Claude cmux notifier preserved"
        if [ ! -x "$hook_script" ]; then
            print_warning "Existing Claude cmux notifier is not executable: $hook_script"
        fi
    fi

    mkdir -p "$HOME/.claude"
    if [ ! -f "$settings" ]; then
        printf '{}\n' > "$settings"
        chmod 600 "$settings"
    fi

    if ! jq empty "$settings" >/dev/null 2>&1; then
        print_warning "Claude settings are not valid JSON; leaving them unchanged: $settings"
        return 0
    fi

    tmp_file="$(mktemp)"
    if jq --arg cmd "$hook_script" '
        .hooks = (.hooks // {})
        | .hooks.Stop = (.hooks.Stop // [])
        | (if any(.hooks.Stop[]?; any(.hooks[]?; ((.command? // "") | endswith("/.claude/hooks/cmux-notify.sh"))))
           then .
           else .hooks.Stop += [{"matcher":"","hooks":[{"type":"command","command":$cmd}]}]
           end)
        | .hooks.PostToolUse = (.hooks.PostToolUse // [])
        | (if any(.hooks.PostToolUse[]?; (.matcher == "Task") and any(.hooks[]?; ((.command? // "") | endswith("/.claude/hooks/cmux-notify.sh"))))
           then .
           else .hooks.PostToolUse += [{"matcher":"Task","hooks":[{"type":"command","command":$cmd}]}]
           end)
    ' "$settings" > "$tmp_file"; then
        if ! cmp -s "$settings" "$tmp_file"; then
            cp "$settings" "$settings.backup.$(date +%Y%m%d_%H%M%S)"
            install -m 600 "$tmp_file" "$settings"
            print_success "Claude Code cmux notification hooks installed"
        else
            print_success "Claude Code cmux notification hooks already configured"
        fi
    else
        print_warning "Could not merge Claude cmux hooks; leaving settings unchanged"
    fi
    rm -f "$tmp_file"
}

setup_cmux_codex_notifications() {
    local codex_dir="$HOME/.codex"
    local config="$codex_dir/config.toml"
    local notify_script="$codex_dir/cmux-notify.sh"
    local notify_line
    local existing_notify
    local tmp_file

    if ! command_exists jq; then
        print_warning "jq is required for Codex cmux notifications; skipping"
        return 0
    fi

    mkdir -p "$codex_dir"

    if [ ! -e "$notify_script" ]; then
        cat > "$notify_script" << 'EOF'
#!/usr/bin/env bash

CMUX="$HOME/.cmux/bin/cmux"
PAYLOAD="${1:-}"

[ -x "$CMUX" ] || exit 0
"$CMUX" ping >/dev/null 2>&1 || exit 0

TYPE="$(printf '%s' "$PAYLOAD" | jq -r '.type // ""')"
[ "$TYPE" = "agent-turn-complete" ] || exit 0

CWD="$(printf '%s' "$PAYLOAD" | jq -r '.cwd // ""')"
PROJECT="$(basename "$CWD")"
[ -n "$PROJECT" ] && [ "$PROJECT" != "." ] || PROJECT="remote"

MESSAGE="$(
    printf '%s' "$PAYLOAD" |
    jq -r '."last-assistant-message" // "Turn complete"'
)"
MESSAGE="${MESSAGE:0:240}"

"$CMUX" notify \
    --title "Codex" \
    --subtitle "$PROJECT" \
    --body "$MESSAGE"

exit 0
EOF
        chmod 700 "$notify_script"
        print_success "Codex cmux notifier installed"
    else
        print_success "Existing Codex cmux notifier preserved"
        if [ ! -x "$notify_script" ]; then
            print_warning "Existing Codex cmux notifier is not executable: $notify_script"
        fi
    fi

    notify_line="notify = [\"$notify_script\"]"

    if [ ! -f "$config" ]; then
        printf '%s\n' "$notify_line" > "$config"
        chmod 600 "$config"
        print_success "Codex cmux notification configured"
        return 0
    fi

    # Only inspect top-level TOML keys (before the first [section]).
    existing_notify="$(awk '
        BEGIN { top = 1 }
        /^\[/ { top = 0 }
        top && /^[[:space:]]*notify[[:space:]]*=/ { print; exit }
    ' "$config")"

    if [ -z "$existing_notify" ]; then
        tmp_file="$(mktemp)"
        {
            printf '%s\n\n' "$notify_line"
            cat "$config"
        } > "$tmp_file"
        cp "$config" "$config.backup.$(date +%Y%m%d_%H%M%S)"
        install -m 600 "$tmp_file" "$config"
        rm -f "$tmp_file"
        print_success "Codex cmux notification added as a top-level notify command"
    elif printf '%s' "$existing_notify" | grep -q 'cmux-notify.sh'; then
        print_success "Codex cmux notification already configured"
    else
        print_warning "Codex already has a different top-level notify command; leaving it unchanged"
    fi
}

setup_cmux_phase_a_integration() {
    print_step "Step 10: Configuring cmux Phase A Remote Integration"

    print_info "cmux remote relay binaries are installed automatically on first 'cmux ssh' connection"
    print_info "This step configures PATH and agent notification bridges without modifying plugin hooks"

    if command_exists claude || [ -f "$HOME/.claude/settings.json" ]; then
        setup_cmux_claude_notifications
    else
        print_warning "Claude Code not installed; skipping Claude cmux notifications"
    fi

    if command_exists codex || [ -d "$HOME/.codex" ]; then
        setup_cmux_codex_notifications
    else
        print_warning "Codex not installed; skipping Codex cmux notifications"
    fi

    print_success "cmux Phase A remote integration configured"
}

#######################################
# Step 11: Install Markdown + TeX Review Helpers
#######################################

setup_mdview_helpers() {
    print_step "Step 11: Installing Markdown + TeX Review Helpers"

    local functions_dir="$HOME/.config/fish/functions"
    local missing=()
    local cmd

    for cmd in fish node npm npx ss ps realpath nohup; do
        command_exists "$cmd" || missing+=("$cmd")
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        print_warning "mdview helpers not installed; missing commands: ${missing[*]}"
        return 0
    fi

    mkdir -p "$functions_dir"

    if [ ! -e "$functions_dir/mdview.fish" ]; then
        cat > "$functions_dir/mdview.fish" << 'EOF'
function __mdview_pid_is_expected --argument-names pid
    set -l process_args (ps -p "$pid" -o args= 2>/dev/null | string collect | string trim)
    string match -rq -- '(@hypersoweak/mdprev|/mdprev)(@0\.1\.1)?([[:space:]]|$)' "$process_args"
end

function __mdview_cleanup_launcher --argument-names launcher_pid
    if not string match -rq -- '^[0-9]+$' "$launcher_pid"
        return
    end

    set -l launcher_pgid (ps -p "$launcher_pid" -o pgid= 2>/dev/null | string trim)
    set -l group_rows (ps -eo pgid=,args= 2>/dev/null)
    set -l expected_group 0
    if string match -rq -- "^[[:space:]]*$launcher_pid[[:space:]].*(@hypersoweak/mdprev|/mdprev)" $group_rows
        set expected_group 1
    end

    if test "$launcher_pgid" = "$launcher_pid"; and test "$expected_group" -eq 1
        command kill -TERM -- -$launcher_pid 2>/dev/null
    else if command kill -0 "$launcher_pid" 2>/dev/null; and __mdview_pid_is_expected "$launcher_pid"
        command kill "$launcher_pid" 2>/dev/null
    end
end

function mdview --description "Start Markdown + TeX preview in background"
    if test (count $argv) -lt 1; or test (count $argv) -gt 2
        echo "Usage: mdview <markdown-file> [port]"
        return 2
    end

    set -l file (realpath -- "$argv[1]" 2>/dev/null)
    if test -z "$file"; or not test -f "$file"
        echo "mdview: file not found: $argv[1]"
        return 1
    end

    set -l port 5173
    if test (count $argv) -eq 2
        set port $argv[2]
    end
    if not string match -rq -- '^[0-9]+$' "$port"
        echo "mdview: invalid port: $port"
        return 2
    end
    if test "$port" -lt 1; or test "$port" -gt 65535
        echo "mdview: port must be between 1 and 65535"
        return 2
    end

    set -l state_dir "$HOME/.cache/mdview"
    set -l pid_file "$state_dir/$port.pid"
    set -l launcher_file "$state_dir/$port.launcher.pid"
    set -l log_file "$state_dir/$port.log"
    mkdir -p "$state_dir"

    set -l listener_line (ss -H -ltnp "sport = :$port" 2>/dev/null | head -n 1)
    if test -n "$listener_line"
        set -l existing_pid (string match -r -g -- 'pid=([0-9]+)' "$listener_line" | head -n 1)
        if test -n "$existing_pid"
            echo "mdview: port $port is already in use (PID $existing_pid)"
        else
            echo "mdview: port $port is already in use"
        end
        echo "Preview: http://localhost:$port"
        return 1
    end

    rm -f "$pid_file" "$launcher_file"

    command nohup npx --yes @hypersoweak/mdprev@0.1.1 "$file" \
        --no-open --port "$port" >"$log_file" 2>&1 &

    set -l launcher_pid $last_pid
    printf '%s\n' "$launcher_pid" > "$launcher_file"

    # A cold npx cache may need time to download the pinned package.
    set -l server_pid ""
    for i in (seq 1 600)
        set listener_line (ss -H -ltnp "sport = :$port" 2>/dev/null | head -n 1)
        if test -n "$listener_line"
            set server_pid (string match -r -g -- 'pid=([0-9]+)' "$listener_line" | head -n 1)
            break
        end
        if not command kill -0 "$launcher_pid" 2>/dev/null; and not command kill -0 -- -$launcher_pid 2>/dev/null
            break
        end
        sleep 0.2
    end

    if test -z "$server_pid"; or not __mdview_pid_is_expected "$server_pid"
        echo "mdview: failed to start the managed preview on port $port"
        echo "Log: $log_file"
        __mdview_cleanup_launcher "$launcher_pid"
        rm -f "$pid_file" "$launcher_file"
        return 1
    end

    printf '%s\n' "$server_pid" > "$pid_file"
    echo "Markdown: $file"
    echo "Preview:  http://localhost:$port"
    echo "PID:      $server_pid"
    echo "Log:      $log_file"
end
EOF
        chmod 644 "$functions_dir/mdview.fish"
        print_success "mdview Fish helper installed"
    else
        print_success "Existing mdview Fish helper preserved"
    fi

    if [ ! -e "$functions_dir/mdview-status.fish" ]; then
        cat > "$functions_dir/mdview-status.fish" << 'EOF'
function __mdview_status_pid_is_expected --argument-names pid
    set -l process_args (ps -p "$pid" -o args= 2>/dev/null | string collect | string trim)
    string match -rq -- '(@hypersoweak/mdprev|/mdprev)(@0\.1\.1)?([[:space:]]|$)' "$process_args"
end

function mdview-status --description "List managed Markdown preview servers"
    set -l state_dir "$HOME/.cache/mdview"
    set -l found 0

    if not test -d "$state_dir"
        echo "No mdview previews running."
        return 0
    end

    printf "%-8s %-10s %s\n" PORT PID STATUS
    for pid_file in "$state_dir"/*.pid
        if string match -q '*.launcher.pid' "$pid_file"; or not test -f "$pid_file"
            continue
        end

        set -l port (basename "$pid_file" .pid)
        set -l pid (head -n 1 "$pid_file" 2>/dev/null | string trim)
        if not string match -rq -- '^[0-9]+$' "$port"; or not string match -rq -- '^[0-9]+$' "$pid"
            printf "%-8s %-10s %s\n" "$port" "INVALID" "INVALID STATE"
            continue
        end

        if command kill -0 "$pid" 2>/dev/null
            set -l listener_line (ss -H -ltnp "sport = :$port" 2>/dev/null | head -n 1)
            if string match -q -- "*pid=$pid,*" "$listener_line"; and __mdview_status_pid_is_expected "$pid"
                printf "%-8s %-10s %s\n" "$port" "$pid" "RUNNING"
                set found 1
            else
                printf "%-8s %-10s %s\n" "$port" "$pid" "PROCESS ALIVE, NOT MATCHING LISTENER"
            end
        else
            printf "%-8s %-10s %s\n" "$port" "$pid" "STALE"
        end
    end

    if test "$found" -eq 0
        echo
        echo "No active mdview listeners found."
    end
end
EOF
        chmod 644 "$functions_dir/mdview-status.fish"
        print_success "mdview-status Fish helper installed"
    else
        print_success "Existing mdview-status Fish helper preserved"
    fi

    if [ ! -e "$functions_dir/mdview-stop.fish" ]; then
        cat > "$functions_dir/mdview-stop.fish" << 'EOF'
function __mdview_stop_pid_is_expected --argument-names pid
    set -l process_args (ps -p "$pid" -o args= 2>/dev/null | string collect | string trim)
    string match -rq -- '(@hypersoweak/mdprev|/mdprev)(@0\.1\.1)?([[:space:]]|$)' "$process_args"
end

function mdview-stop --description "Stop a managed Markdown preview"
    if test (count $argv) -gt 1
        echo "Usage: mdview-stop [port]"
        return 2
    end

    set -l port 5173
    if test (count $argv) -eq 1
        set port $argv[1]
    end
    if not string match -rq -- '^[0-9]+$' "$port"
        echo "mdview-stop: invalid port: $port"
        return 2
    end
    if test "$port" -lt 1; or test "$port" -gt 65535
        echo "mdview-stop: port must be between 1 and 65535"
        return 2
    end

    set -l state_dir "$HOME/.cache/mdview"
    set -l pid_file "$state_dir/$port.pid"
    set -l launcher_file "$state_dir/$port.launcher.pid"

    if not test -f "$pid_file"
        echo "mdview-stop: no managed preview found on port $port"
        return 1
    end

    set -l server_pid (head -n 1 "$pid_file" 2>/dev/null | string trim)
    if not string match -rq -- '^[0-9]+$' "$server_pid"
        echo "mdview-stop: invalid managed PID state"
        return 1
    end

    if command kill -0 "$server_pid" 2>/dev/null
        set -l listener_line (ss -H -ltnp "sport = :$port" 2>/dev/null | head -n 1)
        if not string match -q -- "*pid=$server_pid,*" "$listener_line"; or not __mdview_stop_pid_is_expected "$server_pid"
            echo "mdview-stop: refusing to kill PID $server_pid; it is not the managed mdprev listener"
            return 1
        end

        command kill -TERM "$server_pid" 2>/dev/null
        for i in (seq 1 20)
            if not command kill -0 "$server_pid" 2>/dev/null
                break
            end
            sleep 0.1
        end
        if command kill -0 "$server_pid" 2>/dev/null; and __mdview_stop_pid_is_expected "$server_pid"
            command kill -KILL "$server_pid" 2>/dev/null
        end
    end

    if test -f "$launcher_file"
        set -l launcher_pid (head -n 1 "$launcher_file" 2>/dev/null | string trim)
        if string match -rq -- '^[0-9]+$' "$launcher_pid"; and command kill -0 "$launcher_pid" 2>/dev/null; and __mdview_stop_pid_is_expected "$launcher_pid"
            command kill "$launcher_pid" 2>/dev/null
        end
    end

    rm -f "$pid_file" "$launcher_file"
    echo "Stopped Markdown preview on port $port"
end
EOF
        chmod 644 "$functions_dir/mdview-stop.fish"
        print_success "mdview-stop Fish helper installed"
    else
        print_success "Existing mdview-stop Fish helper preserved"
    fi
}

#######################################
# Main Setup Function
#######################################

main() {
    print_info "This script will set up your RunPod/Docker development environment"
    print_info "It targets the Phase A workflow: macOS cmux/Ghostty -> cmux ssh -> remote tmux -> neovim/agents"
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
    install_neovim_plugins
    setup_cmux_phase_a_integration
    setup_mdview_helpers

    # Print summary
    print_step "Setup Complete!"

    print_success "Your RunPod/Docker environment is now configured!"
    echo ""
    print_info "Next steps:"
    echo "  1. From the Mac, connect with: cmux ssh <host> --name <project>"
    echo "  2. Run 'exec fish' in this existing connection, or reconnect to enter Fish automatically"
    echo "  3. From Fish, start/attach tmux: tmux new-session -A -s <session>"
    echo "  4. Install tmux plugins once: Press Ctrl+a then Shift+I"
    echo "  5. Start neovim / Claude Code / Codex inside tmux"
    echo "  6. In nvim, run: :checkhealth provider"
    echo ""
    print_info "cmux Phase A checks (after connecting from cmux):"
    echo "  - command -v cmux should resolve to $HOME/.cmux/bin/cmux"
    echo "  - cmux ping should return { \"pong\": true }"
    echo "  - Claude Stop/Task and Codex turn-complete notifications should appear in cmux"
    echo "  - mdview <file.md> [port] uses @hypersoweak/mdprev@$MDPREV_VERSION"
    echo "  - Open http://localhost:<port> in the Browser surface; do not publish the RunPod port"
    echo ""
    print_info "Test clipboard integration:"
    echo "  - In remote nvim, select text and press <C-c>"
    echo "  - On local macOS, press Cmd+V to paste"
    echo ""
    print_warning "Phase A transport is cmux ssh + remote tmux. Mosh is intentionally not required."
    print_success "Happy coding!"
}

# Run main function when executed directly (allows sourcing for tests/debugging)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main
fi
