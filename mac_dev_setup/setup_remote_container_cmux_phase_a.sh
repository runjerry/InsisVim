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
#   Interactive mode:          ./setup_remote_container_cmux_phase_a.sh
#   Safe non-interactive mode: ./setup_remote_container_cmux_phase_a.sh -y
#   Explicit replacements:     ./setup_remote_container_cmux_phase_a.sh -f
#   Non-interactive + replace: ./setup_remote_container_cmux_phase_a.sh -yf

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
TMUX_SOURCE_VERSION="3.4"
TMUX_SOURCE_SHA256="551ab8dea0bf505c0ad6b7bb35ef567cdde0ccb84357df142c254f35a23e19aa"
AUTO_YES=false
FORCE=false
FISH_INSTALLED_BY_SCRIPT=false
SETUP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse command line arguments
while getopts "yf" opt; do
    case $opt in
        y) AUTO_YES=true ;;
        f) FORCE=true ;;
        *) echo "Usage: $0 [-y] [-f]"; exit 1 ;;
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

# Replacement/removal is never implied by -y. In interactive mode it is
# individually confirmed; -f is the explicit non-interactive opt-in.
ask_reconfigure() {
    if [ "$FORCE" = true ]; then
        return 0
    fi
    if [ "$AUTO_YES" = true ]; then
        return 1
    fi
    ask_yes_no "$1"
}

backup_file() {
    local source="$1"
    local backup

    backup="$(mktemp "${source}.backup.$(date +%Y%m%d_%H%M%S).XXXXXX")"
    cp -p -- "$source" "$backup"
    print_warning "Backed up $source to $backup"
}

stage_setup_file() {
    local filename="$1"
    local destination="$2"
    local repo_path

    if [ -f "$SETUP_SCRIPT_DIR/$filename" ]; then
        cp -- "$SETUP_SCRIPT_DIR/$filename" "$destination"
        return 0
    fi

    repo_path="${NVIM_CONFIG_REPO#git@github.com:}"
    repo_path="${repo_path%.git}"
    curl -fsSL \
        "https://raw.githubusercontent.com/${repo_path}/${NVIM_CONFIG_BRANCH}/mac_dev_setup/${filename}" \
        -o "$destination"
}

should_install_managed_file() {
    local target="$1"
    local label="$2"

    if [ ! -e "$target" ]; then
        return 0
    fi

    if ask_reconfigure "Replace the existing $label?"; then
        backup_file "$target"
        return 0
    fi

    print_success "Existing $label preserved"
    return 1
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
    elif command_exists dnf; then
        PKG_MANAGER="dnf"
        INSTALL_CMD="$USE_SUDO dnf install -y"
        print_success "Detected: dnf (Fedora)"
    elif command_exists yum; then
        PKG_MANAGER="yum"
        INSTALL_CMD="$USE_SUDO yum install -y"
        print_success "Detected: yum (RHEL/CentOS)"
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
    for cmd in curl wget git less jq ss ps realpath nohup sha256sum cmp awk tar gzip fish rg unzip tmux node npm npx; do
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
        apt-get|pacman)
            install_if_missing ss iproute2
            install_if_missing ps procps
            ;;
        yum|dnf)
            install_if_missing ss iproute
            install_if_missing ps procps-ng
            ;;
    esac
    install_if_missing realpath coreutils
    install_if_missing nohup coreutils
    install_if_missing sha256sum coreutils
    install_if_missing cmp diffutils
    install_if_missing awk gawk
    install_if_missing tar
    install_if_missing gzip

    configure_git_identity
}

configure_git_identity() {
    local desired_name="Jerry Bai"
    local desired_email="qinxun@gmail.com"
    local current_name
    local current_email
    local has_difference=false

    current_name="$(git config --global --get user.name 2>/dev/null || true)"
    current_email="$(git config --global --get user.email 2>/dev/null || true)"

    if [ -z "$current_name" ]; then
        git config --global user.name "$desired_name"
        current_name="$desired_name"
        print_success "Configured missing global Git user.name"
    elif [ "$current_name" != "$desired_name" ]; then
        has_difference=true
    fi

    if [ -z "$current_email" ]; then
        git config --global user.email "$desired_email"
        current_email="$desired_email"
        print_success "Configured missing global Git user.email"
    elif [ "$current_email" != "$desired_email" ]; then
        has_difference=true
    fi

    if [ "$has_difference" = true ]; then
        if ask_reconfigure "Replace the existing global Git identity with this setup's defaults?"; then
            git config --global user.name "$desired_name"
            git config --global user.email "$desired_email"
            print_success "Global Git identity replaced"
        else
            print_warning "Existing global Git identity differs; preserving it"
        fi
    else
        print_success "Global Git identity is configured"
    fi
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
            FISH_INSTALLED_BY_SCRIPT=true
            print_success "Fish installed"
        else
            print_warning "Skipping Fish installation"
        fi
    else
        print_success "Fish already installed: $(fish --version)"
    fi

    # fzf (install from git for key bindings)
    if ! command_exists fzf; then
        if [ -d ~/.fzf ]; then
            print_warning "~/.fzf already exists but fzf is not on PATH; preserving the checkout"
        else
            print_info "Installing fzf from git..."
            git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
            ~/.fzf/install --all --no-bash --no-zsh  # Only fish shell
            print_success "fzf installed with key bindings"
        fi
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
        local build_root
        local archive

        print_info "Building tmux $TMUX_SOURCE_VERSION from source..."
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

        build_root="$(mktemp -d)"
        archive="$build_root/tmux-${TMUX_SOURCE_VERSION}.tar.gz"
        wget -q -O "$archive" \
            "https://github.com/tmux/tmux/releases/download/${TMUX_SOURCE_VERSION}/tmux-${TMUX_SOURCE_VERSION}.tar.gz"
        if ! printf '%s  %s\n' "$TMUX_SOURCE_SHA256" "$archive" | sha256sum -c -; then
            rm -rf "$build_root"
            print_error "tmux source checksum verification failed"
            return 1
        fi
        tar xzf "$archive" -C "$build_root"
        if ! (
            cd "$build_root/tmux-${TMUX_SOURCE_VERSION}" &&
            ./configure &&
            make &&
            $USE_SUDO make install
        ); then
            rm -rf "$build_root"
            print_error "tmux source build failed"
            return 1
        fi
        rm -rf "$build_root"
        print_success "tmux $TMUX_SOURCE_VERSION installed from source"
    }

    if command_exists tmux; then
        TMUX_VERSION=$(tmux -V | sed 's/tmux //')
        # Extract major.minor version for comparison
        TMUX_MAJOR=$(echo "$TMUX_VERSION" | cut -d. -f1)
        TMUX_MINOR=$(echo "$TMUX_VERSION" | cut -d. -f2 | cut -d- -f1 | tr -dc '0-9')

        if [ "$TMUX_MAJOR" -lt 3 ] || ([ "$TMUX_MAJOR" -eq 3 ] && [ "$TMUX_MINOR" -lt 3 ]); then
            print_warning "tmux $TMUX_VERSION is installed, but 3.3+ is required for OSC 52 clipboard"
            if ask_reconfigure "Replace the existing tmux command with a 3.4 source build?"; then
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
                if ! curl -fsSL https://deb.nodesource.com/setup_lts.x -o "$node_setup"; then
                    rm -f "$node_setup"
                    print_error "Failed to download the NodeSource setup script"
                    return 1
                fi
                if ! $USE_SUDO bash "$node_setup"; then
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

    # npm and npx are required by Codex and the mdview helpers. Some distro
    # Node packages do not include them.
    if ! command_exists npm || ! command_exists npx; then
        if ask_yes_no "Install npm/npx? (required for Codex and mdview)"; then
            print_info "Installing npm..."
            $INSTALL_CMD npm
        else
            print_warning "Skipping npm/npx; Codex and mdview installation may be unavailable"
        fi
    fi

    if command_exists npm; then
        print_success "npm available: $(npm --version)"
    else
        print_warning "npm is unavailable"
    fi
    if command_exists npx; then
        print_success "npx available: $(npx --version)"
    else
        print_warning "npx is unavailable"
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
    FISH_PATH=$(command -v fish)
    print_info "Fish located at: $FISH_PATH"

    # Add fish to allowed shells if not already there
    if [ -f /etc/shells ] && ! grep -Fxq "$FISH_PATH" /etc/shells; then
        print_info "Adding fish to /etc/shells..."
        echo "$FISH_PATH" | $USE_SUDO tee -a /etc/shells > /dev/null
        print_success "Fish added to allowed shells"
    else
        print_success "Fish already in allowed shells"
    fi

    local login_shell
    local tmux_default_shell
    local configure_default=false

    login_shell="$(getent passwd "$(id -un)" 2>/dev/null | awk -F: '{print $7}')"
    tmux_default_shell="$(tmux show-options -gv default-shell 2>/dev/null || true)"

    if [ "$login_shell" = "$FISH_PATH" ]; then
        print_success "Fish is already the login shell"
        return
    fi

    # An established tmux workflow that already launches Fish is authoritative.
    # Do not change its login shell during a safe rerun.
    if [ "$FORCE" != true ] && {
        [ "$tmux_default_shell" = "$FISH_PATH" ] ||
        grep -Eq 'default-shell[[:space:]].*fish' "$HOME/.tmux.conf" 2>/dev/null
    }; then
        print_success "Existing tmux workflow already uses Fish; preserving login shell"
        return
    fi

    if [ "$FORCE" = true ]; then
        configure_default=true
    elif [ "$AUTO_YES" = true ]; then
        if [ "$FISH_INSTALLED_BY_SCRIPT" = true ]; then
            configure_default=true
        else
            print_warning "Fish pre-existed without a managed default-shell setting; preserving login shell"
        fi
    elif ask_yes_no "Set Fish as your default shell?"; then
        configure_default=true
    fi

    # Try chsh first, fall back to .bashrc if it fails.
    if [ "$configure_default" = true ]; then
        print_info "Trying chsh to set default shell..."
        if command_exists chsh && $USE_SUDO chsh -s "$FISH_PATH" "$(id -un)" 2>/dev/null; then
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
        print_warning "Fish login-shell behavior left unchanged. Run 'exec fish' when needed"
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

    local fish_dir="$HOME/.config/fish"
    local fish_config="$fish_dir/config.fish"
    local fish_plugins="$fish_dir/fish_plugins"
    local config_changed=false
    local plugins_preexisted=false
    local plugins_changed=false
    local tmp_file

    mkdir -p "$fish_dir" "$fish_dir/conf.d" "$fish_dir/functions"

    if [ -f "$fish_config" ]; then
        if ask_reconfigure "Replace the existing Fish config.fish?"; then
            tmp_file="$(mktemp)"
            if stage_setup_file fish_config.fish "$tmp_file"; then
                backup_file "$fish_config"
                install -m 644 "$tmp_file" "$fish_config"
                config_changed=true
                print_success "Fish config.fish replaced"
            else
                print_warning "Could not stage Fish config; preserving the existing file"
            fi
            rm -f "$tmp_file"
        else
            print_success "Existing Fish config.fish preserved"
        fi
    else
        tmp_file="$(mktemp)"
        if stage_setup_file fish_config.fish "$tmp_file"; then
            install -m 644 "$tmp_file" "$fish_config"
            print_success "Fish config.fish installed"
        else
            print_warning "Failed to download Fish config; creating an empty base config"
            install -m 644 /dev/null "$fish_config"
        fi
        rm -f "$tmp_file"
        config_changed=true
    fi

    # Only alter config.fish when it was installed/replaced in this run.
    if [ "$config_changed" = true ] &&
       ! grep -q "PIP_BREAK_SYSTEM_PACKAGES" "$fish_config" 2>/dev/null; then
        cat >> "$fish_config" << 'EOF'

# Allow pip to install system-wide in containers
set -gx PIP_BREAK_SYSTEM_PACKAGES 1
EOF
        print_success "Container Python setting added to managed Fish config"
    elif ! grep -q "PIP_BREAK_SYSTEM_PACKAGES" "$fish_config" 2>/dev/null; then
        print_warning "Existing Fish config has no PIP_BREAK_SYSTEM_PACKAGES setting; preserving it"
    fi

    [ -f "$fish_plugins" ] && plugins_preexisted=true

    # Fisher's bootstrap can rewrite fish_plugins. Preserve a pre-existing list
    # byte-for-byte around the bootstrap and never update it in safe mode.
    if [ ! -f "$fish_dir/functions/fisher.fish" ]; then
        local saved_plugins=""
        if [ "$plugins_preexisted" = true ]; then
            saved_plugins="$(mktemp)"
            cp -p -- "$fish_plugins" "$saved_plugins"
        fi

        print_info "Installing Fisher (Fish plugin manager)..."
        if fish -c "curl -fsSL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher"; then
            print_success "Fisher installed"
        else
            print_warning "Fisher bootstrap failed"
        fi

        if [ -n "$saved_plugins" ]; then
            cp -p -- "$saved_plugins" "$fish_plugins"
            rm -f "$saved_plugins"
        fi
    else
        print_success "Fisher already installed"
    fi

    if [ "$plugins_preexisted" = true ]; then
        if ask_reconfigure "Replace fish_plugins and update managed Fish plugins?"; then
            plugins_changed=true
        else
            print_success "Existing fish_plugins and installed plugins preserved"
        fi
    else
        plugins_changed=true
    fi

    if [ "$plugins_changed" = true ]; then
        tmp_file="$(mktemp)"
        if stage_setup_file fish_plugins "$tmp_file"; then
            if [ "$plugins_preexisted" = true ]; then
                backup_file "$fish_plugins"
            fi
            install -m 644 "$tmp_file" "$fish_plugins"
            if [ -f "$fish_dir/functions/fisher.fish" ]; then
                print_info "Installing declared Fish plugins..."
                if fish -c "fisher update"; then
                    print_success "Declared Fish plugins installed"
                else
                    print_warning "Some Fish plugins could not be installed"
                fi
            else
                print_warning "fish_plugins installed, but Fisher is unavailable"
            fi
        else
            print_warning "Failed to stage fish_plugins"
        fi
        rm -f "$tmp_file"
    fi

    # cmux installs its remote CLI relay under ~/.cmux/bin on first `cmux ssh`.
    # Keep the path configured even before the relay exists, but preserve an
    # existing validated file during a safe rerun.
    local cmux_fish="$fish_dir/conf.d/99-cmux.fish"
    local write_cmux_fish=false

    if [ -e "$cmux_fish" ]; then
        if ask_reconfigure "Replace the existing 99-cmux.fish?"; then
            backup_file "$cmux_fish"
            write_cmux_fish=true
        else
            print_success "Existing cmux Fish PATH configuration preserved"
        fi
    else
        write_cmux_fish=true
    fi

    if [ "$write_cmux_fish" = true ]; then
        tmp_file="$(mktemp)"
        cat > "$tmp_file" << 'EOF'
# cmux remote CLI relay (installed automatically by `cmux ssh`)
fish_add_path $HOME/.cmux/bin
EOF
        install -m 644 "$tmp_file" "$cmux_fish"
        rm -f "$tmp_file"
        print_success "cmux remote CLI path configured for new Fish shells"
    elif ! grep -Eq 'fish_add_path.*\.cmux/bin' "$cmux_fish" 2>/dev/null; then
        print_warning "Existing 99-cmux.fish does not visibly add ~/.cmux/bin; use -f to replace it"
    fi
}

#######################################
# Step 6: Setup tmux Configuration
#######################################

setup_tmux() {
    print_step "Step 6: Configuring tmux with OSC 52 Support"

    local tmux_config="$HOME/.tmux.conf"
    local replace_tmux=false
    local tmp_file

    if [ -f "$tmux_config" ]; then
        if ask_reconfigure "Replace the existing ~/.tmux.conf?"; then
            replace_tmux=true
        else
            print_success "Existing ~/.tmux.conf preserved"
        fi
    else
        replace_tmux=true
    fi

    if [ "$replace_tmux" = true ]; then
        tmp_file="$(mktemp)"
        if stage_setup_file tmux.conf "$tmp_file"; then
            if [ -f "$tmux_config" ]; then
                backup_file "$tmux_config"
            fi
            install -m 644 "$tmp_file" "$tmux_config"
            print_success "tmux configuration installed at ~/.tmux.conf"
        else
            print_error "Failed to stage tmux configuration; existing state was not changed"
        fi
        rm -f "$tmp_file"
    fi

    # Deliberately do not source-file the config or mutate a running tmux
    # server. Existing sessions remain the persistence authority.

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
        if ! ask_reconfigure "Replace the existing Neovim with $NEOVIM_VERSION?"; then
            print_success "Existing Neovim preserved"
            return
        fi
    fi

    # Detect architecture
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        NVIM_ARCH="linux64"
    elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
        print_warning "Neovim $NEOVIM_VERSION has no equivalent official linux64 ARM archive"
        print_warning "Preserving the system; install an ARM build through the platform package manager"
        return
    else
        print_error "Unsupported architecture: $ARCH"
        return
    fi

    print_info "Downloading Neovim $NEOVIM_VERSION for $ARCH..."
    local tmp_dir
    local archive
    local extracted
    local install_dir="/usr/local/nvim-${NEOVIM_VERSION}"
    local staged_dir="/usr/local/.nvim-${NEOVIM_VERSION}.new.$$"
    local old_dir=""

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
    $USE_SUDO rm -rf "$staged_dir"
    $USE_SUDO mv "$extracted" "$staged_dir"
    if [ -e "$install_dir" ]; then
        old_dir="${install_dir}.backup.$(date +%Y%m%d_%H%M%S).$$"
        $USE_SUDO mv "$install_dir" "$old_dir"
        print_warning "Previous Neovim directory preserved at $old_dir"
    fi
    $USE_SUDO mv "$staged_dir" "$install_dir"
    $USE_SUDO ln -sfn "$install_dir/bin/nvim" /usr/local/bin/nvim
    rm -rf "$tmp_dir"

    print_success "Neovim $NEOVIM_VERSION installed: $(nvim --version | head -n1)"
}

#######################################
# Step 8: Setup Neovim Configuration
#######################################

setup_neovim_config() {
    print_step "Step 8: Setting up Neovim Configuration"

    # Clean up existing nvim configs only after explicit replacement consent.
    if [ -d ~/.config/nvim ] || [ -d ~/.local/share/nvim ] || [ -d ~/.cache/nvim ]; then
        print_warning "Existing Neovim configuration detected"
        if ask_reconfigure "Remove existing Neovim config/data/cache and start fresh?"; then
            print_info "Removing existing Neovim data..."
            rm -rf ~/.local/share/nvim
            rm -rf ~/.cache/nvim
            rm -rf ~/.config/nvim
            print_success "Existing configs removed"
        elif [ -d ~/.config/nvim ]; then
            print_success "Existing Neovim config/data/cache preserved"
            return
        else
            print_warning "Existing Neovim data/cache preserved; adding only the missing config checkout"
        fi
    fi

    # Clone nvim config repository
    if [ ! -d ~/.config/nvim ]; then
        local repo_path="${NVIM_CONFIG_REPO#git@github.com:}"
        local https_repo
        repo_path="${repo_path%.git}"
        https_repo="https://github.com/${repo_path}.git"

        print_info "Cloning Neovim config branch $NVIM_CONFIG_BRANCH..."
        if ! git clone --branch "$NVIM_CONFIG_BRANCH" --single-branch \
            "$https_repo" ~/.config/nvim; then
            rm -rf ~/.config/nvim
            print_warning "HTTPS clone failed; trying the configured repository URL"
            git clone --branch "$NVIM_CONFIG_BRANCH" --single-branch \
                "$NVIM_CONFIG_REPO" ~/.config/nvim
        fi
        print_success "Neovim config cloned (branch: $NVIM_CONFIG_BRANCH)"
    else
        print_success "~/.config/nvim already exists"
    fi

    print_warning "First launch of Neovim will install plugins automatically"
    print_info "This may take a few minutes..."
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

    if command_exists pylsp && command_exists black; then
        print_success "Python LSP and black already available"
    elif ! ask_yes_no "Install missing Python LSP/formatter tools?"; then
        print_warning "Skipping Python tools"
    else
        local python_packages=()
        command_exists pylsp || python_packages+=(python-lsp-server)
        command_exists black || python_packages+=(black)

        if command_exists pip3; then
            pip3 install --user "${python_packages[@]}" 2>/dev/null || pip3 install "${python_packages[@]}"
            print_success "Python LSP and black installed"
        elif command_exists pip; then
            pip install --user "${python_packages[@]}" 2>/dev/null || pip install "${python_packages[@]}"
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
            if ! curl -fsSL https://claude.ai/install.sh -o "$claude_installer"; then
                rm -f "$claude_installer"
                print_error "Failed to download the Claude Code installer"
                return 1
            fi
            if ! bash "$claude_installer"; then
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
                npm install -g @openai/codex
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

    if should_install_managed_file "$hook_script" "Claude cmux notifier"; then
        tmp_file="$(mktemp)"
        cat > "$tmp_file" << 'EOF'
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
        install -m 700 "$tmp_file" "$hook_script"
        rm -f "$tmp_file"
        print_success "Claude cmux notifier installed"
    elif [ ! -x "$hook_script" ]; then
        print_warning "Existing Claude cmux notifier is not executable; use -f to replace it"
    fi

    mkdir -p "$HOME/.claude"
    if [ ! -f "$settings" ]; then
        tmp_file="$(mktemp)"
        printf '{}\n' > "$tmp_file"
        install -m 600 "$tmp_file" "$settings"
        rm -f "$tmp_file"
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
            backup_file "$settings"
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

    if should_install_managed_file "$notify_script" "Codex cmux notifier"; then
        tmp_file="$(mktemp)"
        cat > "$tmp_file" << 'EOF'
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
        install -m 700 "$tmp_file" "$notify_script"
        rm -f "$tmp_file"
        print_success "Codex cmux notifier installed"
    elif [ ! -x "$notify_script" ]; then
        print_warning "Existing Codex cmux notifier is not executable; use -f to replace it"
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
        backup_file "$config"
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

install_mdview_loopback_guard() {
    local guard="$HOME/.local/share/mdview/force-loopback.cjs"
    local tmp_file

    mkdir -p "$(dirname "$guard")"

    if [ -f "$guard" ] &&
       grep -q 'CMUX_PHASE_A_MDVIEW_LOOPBACK_GUARD=1' "$guard" &&
       [ "$FORCE" != true ]; then
        print_success "Existing mdview loopback guard preserved"
        return 0
    fi

    if ! should_install_managed_file "$guard" "mdview loopback guard"; then
        print_warning "Cannot safely install mdview without a verified loopback guard"
        return 1
    fi

    tmp_file="$(mktemp)"
    cat > "$tmp_file" << 'EOF'
// CMUX_PHASE_A_MDVIEW_LOOPBACK_GUARD=1
// @hypersoweak/mdprev 0.1.1 has no host option and otherwise listens on all
// interfaces. Constrain TCP servers in this one process tree to IPv4 loopback.
const net = require("node:net");
const originalListen = net.Server.prototype.listen;

net.Server.prototype.listen = function (...args) {
  if (typeof args[0] === "number") {
    if (typeof args[1] === "string") {
      args[1] = "127.0.0.1";
    } else {
      args.splice(1, 0, "127.0.0.1");
    }
  } else if (
    args[0] &&
    typeof args[0] === "object" &&
    !Object.prototype.hasOwnProperty.call(args[0], "path")
  ) {
    args[0] = { ...args[0], host: "127.0.0.1" };
  }
  return originalListen.apply(this, args);
};
EOF
    install -m 644 "$tmp_file" "$guard"
    rm -f "$tmp_file"
    print_success "mdview loopback guard installed"
}

setup_mdview_helpers() {
    print_step "Step 11: Installing Markdown + TeX Review Helpers"

    local missing=()
    local functions_dir="$HOME/.config/fish/functions"
    local target
    local tmp_file
    local node_major
    local npm_major
    local fish_major
    local fish_minor

    for cmd in fish node npm npx ss ps realpath nohup; do
        command_exists "$cmd" || missing+=("$cmd")
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        print_warning "Cannot install usable mdview helpers; missing: ${missing[*]}"
        return 0
    fi

    node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || true)"
    npm_major="$(npm --version 2>/dev/null | cut -d. -f1)"
    fish_major="$(fish --version 2>/dev/null | awk '{print $3}' | cut -d. -f1)"
    fish_minor="$(fish --version 2>/dev/null | awk '{print $3}' | cut -d. -f2)"

    if ! [[ "$node_major" =~ ^[0-9]+$ ]] || [ "$node_major" -lt 18 ]; then
        print_warning "mdview requires Node.js 18+; preserving the existing Node installation"
        return 0
    fi
    if ! [[ "$npm_major" =~ ^[0-9]+$ ]] || [ "$npm_major" -lt 7 ]; then
        print_warning "mdview requires npm/npx 7+ for non-interactive pinned execution"
        return 0
    fi
    if ! [[ "$fish_major" =~ ^[0-9]+$ ]] ||
       ! [[ "$fish_minor" =~ ^[0-9]+$ ]] ||
       [ "$fish_major" -lt 3 ] ||
       { [ "$fish_major" -eq 3 ] && [ "$fish_minor" -lt 1 ]; }; then
        print_warning "mdview helpers require Fish 3.1+; preserving the existing Fish installation"
        return 0
    fi

    mkdir -p "$functions_dir"

    target="$functions_dir/mdview.fish"
    if should_install_managed_file "$target" "mdview Fish helper"; then
        if install_mdview_loopback_guard; then
            tmp_file="$(mktemp)"
            cat > "$tmp_file" << 'EOF'
function __mdview_pid_is_expected --argument-names pid
    set -l process_args (ps -p "$pid" -o args= 2>/dev/null | string collect | string trim)
    string match -rq -- '(@hypersoweak/mdprev|/mdprev)(@0\.1\.1)?([[:space:]]|$)' "$process_args"
end

function __mdview_group_is_expected --argument-names pgid
    set -l rows (ps -eo pgid=,args= 2>/dev/null)
    string match -rq -- "^[[:space:]]*$pgid[[:space:]].*(@hypersoweak/mdprev|/mdprev)" $rows
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
    set -l loopback_guard "$HOME/.local/share/mdview/force-loopback.cjs"

    if not test -r "$loopback_guard"
        echo "mdview: loopback safety guard is missing: $loopback_guard"
        return 1
    end

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

    set -l forced_node_options "--require=$loopback_guard"
    if set -q NODE_OPTIONS; and test -n "$NODE_OPTIONS"
        set forced_node_options "$NODE_OPTIONS $forced_node_options"
    end

    command nohup env NODE_OPTIONS="$forced_node_options" \
        npx --yes @hypersoweak/mdprev@0.1.1 "$file" \
        --no-open --port "$port" >"$log_file" 2>&1 &

    set -l launcher_pid $last_pid
    set -l launcher_pgid (ps -p "$launcher_pid" -o pgid= 2>/dev/null | string trim)
    if test -z "$launcher_pgid"; or test "$launcher_pgid" != "$launcher_pid"
        echo "mdview: could not create an isolated launcher process group"
        if command kill -0 "$launcher_pid" 2>/dev/null
            command kill "$launcher_pid" 2>/dev/null
        end
        echo "Log: $log_file"
        return 1
    end
    printf '%s\n' "$launcher_pid" > "$launcher_file"

    # Allow up to two minutes for a cold npx cache to download mdprev.
    set -l server_pid ""
    set -l started 0
    set -l failure_reason "timed out waiting for mdprev"

    for i in (seq 1 600)
        set listener_line (ss -H -ltnp "sport = :$port" 2>/dev/null | head -n 1)
        if test -n "$listener_line"
            set server_pid (string match -r -g -- 'pid=([0-9]+)' "$listener_line" | head -n 1)
            if test -z "$server_pid"
                set failure_reason "listener PID is not visible"
                break
            end

            set -l server_pgid (ps -p "$server_pid" -o pgid= 2>/dev/null | string trim)
            if test "$server_pgid" != "$launcher_pid"; or not __mdview_pid_is_expected "$server_pid"
                set failure_reason "requested port was taken by another process"
                set server_pid ""
                break
            end
            if not string match -q -- "*127.0.0.1:$port*" "$listener_line"
                set failure_reason "mdprev did not bind exclusively to IPv4 loopback"
                set server_pid ""
                break
            end

            set started 1
            break
        end

        if not command kill -0 -- -$launcher_pid 2>/dev/null
            set failure_reason "launcher exited before opening the requested port"
            break
        end
        sleep 0.2
    end

    if test "$started" -ne 1
        echo "mdview: failed to start preview ($failure_reason)"
        echo "Log: $log_file"

        if __mdview_group_is_expected "$launcher_pid"
            command kill -TERM -- -$launcher_pid 2>/dev/null
            for i in (seq 1 20)
                if not command kill -0 -- -$launcher_pid 2>/dev/null
                    break
                end
                sleep 0.1
            end
            if command kill -0 -- -$launcher_pid 2>/dev/null; and __mdview_group_is_expected "$launcher_pid"
                command kill -KILL -- -$launcher_pid 2>/dev/null
            end
        else if command kill -0 "$launcher_pid" 2>/dev/null; and __mdview_pid_is_expected "$launcher_pid"
            command kill "$launcher_pid" 2>/dev/null
        end

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
            install -m 644 "$tmp_file" "$target"
            rm -f "$tmp_file"
            print_success "mdview Fish helper installed"
        else
            print_warning "mdview Fish helper was not changed"
        fi
    fi

    target="$functions_dir/mdview-status.fish"
    if should_install_managed_file "$target" "mdview-status Fish helper"; then
        tmp_file="$(mktemp)"
        cat > "$tmp_file" << 'EOF'
function __mdview_status_pid_is_expected --argument-names pid
    set -l process_args (ps -p "$pid" -o args= 2>/dev/null | string collect | string trim)
    string match -rq -- '(@hypersoweak/mdprev|/mdprev)(@0\.1\.1)?([[:space:]]|$)' "$process_args"
end

function mdview-status --description "List managed Markdown preview servers"
    set -l state_dir "$HOME/.cache/mdview"
    set -l records 0
    set -l active 0

    if not test -d "$state_dir"
        echo "No mdview previews running."
        return 0
    end

    printf "%-8s %-10s %s\n" PORT PID STATUS
    for pid_file in "$state_dir"/*.pid
        if string match -q '*.launcher.pid' "$pid_file"; or not test -f "$pid_file"
            continue
        end
        set records (math "$records + 1")

        set -l port (basename "$pid_file" .pid)
        set -l pid (head -n 1 "$pid_file" 2>/dev/null | string trim)
        if not string match -rq -- '^[0-9]+$' "$port"; or not string match -rq -- '^[0-9]+$' "$pid"
            set -l display_pid "$pid"
            test -n "$display_pid"; or set display_pid INVALID
            printf "%-8s %-10s %s\n" "$port" "$display_pid" "INVALID STATE"
            continue
        end

        if command kill -0 "$pid" 2>/dev/null
            set -l listener_line (ss -H -ltnp "sport = :$port" 2>/dev/null | head -n 1)
            if string match -q -- "*pid=$pid,*" "$listener_line"; and __mdview_status_pid_is_expected "$pid"
                if string match -q -- "*127.0.0.1:$port*" "$listener_line"
                    printf "%-8s %-10s %s\n" "$port" "$pid" "RUNNING"
                else
                    printf "%-8s %-10s %s\n" "$port" "$pid" "RUNNING, NON-LOOPBACK BIND"
                end
                set active (math "$active + 1")
            else
                printf "%-8s %-10s %s\n" "$port" "$pid" "PROCESS ALIVE, NOT MATCHING LISTENER"
            end
        else
            printf "%-8s %-10s %s\n" "$port" "$pid" "STALE"
        end
    end

    if test "$records" -eq 0
        echo "No managed mdview state files found."
    else if test "$active" -eq 0
        echo
        echo "No active mdview listeners found."
    end
end
EOF
        install -m 644 "$tmp_file" "$target"
        rm -f "$tmp_file"
        print_success "mdview-status Fish helper installed"
    fi

    target="$functions_dir/mdview-stop.fish"
    if should_install_managed_file "$target" "mdview-stop Fish helper"; then
        tmp_file="$(mktemp)"
        cat > "$tmp_file" << 'EOF'
function __mdview_stop_pid_is_expected --argument-names pid
    set -l process_args (ps -p "$pid" -o args= 2>/dev/null | string collect | string trim)
    string match -rq -- '(@hypersoweak/mdprev|/mdprev)(@0\.1\.1)?([[:space:]]|$)' "$process_args"
end

function __mdview_stop_group_is_expected --argument-names pgid
    set -l rows (ps -eo pgid=,args= 2>/dev/null)
    string match -rq -- "^[[:space:]]*$pgid[[:space:]].*(@hypersoweak/mdprev|/mdprev)" $rows
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

    if not test -f "$pid_file"; and not test -f "$launcher_file"
        echo "mdview-stop: no managed preview found on port $port"
        return 1
    end

    set -l server_pid ""
    set -l launcher_pid ""
    test -f "$pid_file"; and set server_pid (head -n 1 "$pid_file" 2>/dev/null | string trim)
    test -f "$launcher_file"; and set launcher_pid (head -n 1 "$launcher_file" 2>/dev/null | string trim)

    set -l managed_server 0
    set -l server_pgid ""
    if test -n "$server_pid"
        if not string match -rq -- '^[0-9]+$' "$server_pid"
            echo "mdview-stop: stale invalid server PID state"
            set server_pid ""
        else if command kill -0 "$server_pid" 2>/dev/null
            set -l listener_line (ss -H -ltnp "sport = :$port" 2>/dev/null | head -n 1)
            if string match -q -- "*pid=$server_pid,*" "$listener_line"; and __mdview_stop_pid_is_expected "$server_pid"
                set managed_server 1
                set server_pgid (ps -p "$server_pid" -o pgid= 2>/dev/null | string trim)
            else
                echo "mdview-stop: refusing to kill PID $server_pid; it is not the managed mdprev listener"
                return 1
            end
        end
    end

    set -l kill_group 0
    if string match -rq -- '^[0-9]+$' "$launcher_pid"; and \
       command kill -0 -- -$launcher_pid 2>/dev/null; and \
       __mdview_stop_group_is_expected "$launcher_pid"
        if test "$managed_server" -eq 0; or test "$server_pgid" = "$launcher_pid"
            set kill_group 1
        end
    end

    if test "$kill_group" -eq 1
        command kill -TERM -- -$launcher_pid 2>/dev/null
        for i in (seq 1 20)
            if not command kill -0 -- -$launcher_pid 2>/dev/null
                break
            end
            sleep 0.1
        end
        if command kill -0 -- -$launcher_pid 2>/dev/null; and __mdview_stop_group_is_expected "$launcher_pid"
            command kill -KILL -- -$launcher_pid 2>/dev/null
        end
    else if test "$managed_server" -eq 1
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

    if test "$kill_group" -eq 0; and string match -rq -- '^[0-9]+$' "$launcher_pid"; and \
       command kill -0 "$launcher_pid" 2>/dev/null; and __mdview_stop_pid_is_expected "$launcher_pid"
        command kill "$launcher_pid" 2>/dev/null
    end

    rm -f "$pid_file" "$launcher_file"
    if test "$managed_server" -eq 1; or test "$kill_group" -eq 1
        echo "Stopped Markdown preview on port $port"
    else
        echo "Removed stale mdview state for port $port"
    end
end
EOF
        install -m 644 "$tmp_file" "$target"
        rm -f "$tmp_file"
        print_success "mdview-stop Fish helper installed"
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
    if [ "$FORCE" = true ]; then
        print_warning "Replacement mode enabled (-f): selected managed configs may be backed up and replaced"
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
    setup_cmux_phase_a_integration
    setup_mdview_helpers

    # Print summary
    print_step "Setup Complete!"

    print_success "Your RunPod/Docker environment is now configured!"
    echo ""
    print_info "Next steps:"
    echo "  1. From the Mac, connect with: cmux ssh <host> --name <project>"
    echo "  2. Start a new Fish shell if needed: exec fish (or reconnect)"
    echo "  3. Start/attach tmux: tmux new-session -A -s <session>"
    echo "  4. Install tmux plugins once: Press Ctrl+a then Shift+I"
    echo "  5. Start neovim / Claude Code / Codex inside tmux"
    echo "  6. In nvim, run: :checkhealth provider"
    echo "  7. For Markdown + TeX: mdview <file.md> [port], then open http://localhost:<port> in cmux Browser"
    echo ""
    print_info "cmux Phase A checks (after connecting from cmux):"
    echo "  - command -v cmux should resolve to $HOME/.cmux/bin/cmux"
    echo "  - cmux ping should return { \"pong\": true }"
    echo "  - Claude Stop/Task and Codex turn-complete notifications should appear in cmux"
    echo "  - mdview-status should report its listener as RUNNING on IPv4 loopback"
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
