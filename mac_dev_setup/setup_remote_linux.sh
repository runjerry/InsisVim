#!/usr/bin/env bash

# Native Linux development setup (tested on Ubuntu 24.04 x86_64).
# macOS Alacritty/cmux -> SSH -> Fish/tmux -> Neovim/agents.
# Keep the common tools and cmux helpers aligned with the Phase A container
# script, but use chsh and isolated Python tools on native hosts.
# Run as the account to configure; sudo is used only for system changes.
# Usage: ./setup_remote_linux.sh [-y]

set -euo pipefail

echo "============================================"
echo "Native Linux Development Setup"
echo "============================================"
echo ""

#######################################
# Configuration Variables
#######################################

NVIM_CONFIG_REPO="${NVIM_CONFIG_REPO:-https://github.com/runjerry/InsisVim.git}"
NVIM_CONFIG_BRANCH="${NVIM_CONFIG_BRANCH:-linux-server-setup}"
NEOVIM_VERSION="v0.9.5"
NEOVIM_LINUX64_SHA256="44ee395d9b5f8a14be8ec00d3b8ead34e18fe6461e40c9c8c50e6956d643b6ca"
TMUX_SOURCE_SHA256="551ab8dea0bf505c0ad6b7bb35ef567cdde0ccb84357df142c254f35a23e19aa"
MDPREV_VERSION="0.1.1"
AUTO_YES=false
BACKUP_DIR="${INSIS_BACKUP_DIR:-$HOME/.local/state/insis-setup/backups/$(date +%Y%m%d_%H%M%S)-$$}"
SETUP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Make user-local tools installed by the baseline setup visible immediately in
# this run; Fish persists the same paths for future sessions.
export PATH="$HOME/.local/bin:$HOME/.node_modules/bin:$HOME/.fzf/bin:/usr/local/bin:$PATH"

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
    local yn
    while read -r -p "$1 (y/n): " yn; do
        case "$yn" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
    print_warning "No answer available; skipping. Use -y for unattended setup."
    return 1
}

# Back up each original file once per run, including files containing secrets.
backup_file() {
    local target="$1"
    local saved="$BACKUP_DIR/${target#/}"
    if [ -e "$target" ] && [ ! -e "$saved" ]; then
        mkdir -p "$BACKUP_DIR"
        chmod 700 "$BACKUP_DIR"
        mkdir -p "$(dirname "$saved")"
        cp -a "$target" "$saved"
        print_info "Backup: $saved"
    fi
}

repo_path() {
    local repo="${NVIM_CONFIG_REPO#git@github.com:}"
    repo="${repo#https://github.com/}"
    repo="${repo%.git}"
    printf '%s\n' "$repo"
}

fetch_template() {
    local name="$1" target="$2"
    if [ -f "$SETUP_SCRIPT_DIR/$name" ]; then
        cp "$SETUP_SCRIPT_DIR/$name" "$target"
    else
        curl -fLSs --retry 3 \
            "https://raw.githubusercontent.com/$(repo_path)/${NVIM_CONFIG_BRANCH}/mac_dev_setup/$name" \
            -o "$target"
    fi
}

install_template() {
    local name="$1" target="$2" mode="${3:-644}" tmp_file
    tmp_file="$(mktemp)"
    if ! fetch_template "$name" "$tmp_file"; then
        rm -f "$tmp_file"
        print_error "Could not fetch $name; existing configuration was preserved"
        return 1
    fi
    if ! cmp -s "$tmp_file" "$target"; then
        backup_file "$target"
        mkdir -p "$(dirname "$target")"
        install -m "$mode" "$tmp_file" "$target"
    fi
    rm -f "$tmp_file"
}

setup_prompt_editor() {
    local target="$HOME/.local/bin/nvim-prompt-editor" tmp_file
    tmp_file="$(mktemp)"
    cat > "$tmp_file" << 'EOF'
#!/bin/sh
# Preserve pasted prompt text even when bracketed paste is unavailable.
exec nvim -c 'set paste' "$@"
EOF
    if ! cmp -s "$tmp_file" "$target"; then
        backup_file "$target"
        mkdir -p "$HOME/.local/bin"
        install -m 755 "$tmp_file" "$target"
    fi
    rm -f "$tmp_file"
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
    # Using `sudo ./script` would configure root rather than the calling user.
    if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
        print_error "Run this script without sudo as $SUDO_USER; it escalates system commands itself."
        return 1
    fi
    if [ "$EUID" -eq 0 ]; then
        USE_SUDO=""
        print_success "Configuring root's development environment"
    elif command_exists sudo; then
        sudo -v
        USE_SUDO="sudo"
    else
        print_error "System package installation requires root or sudo."
        return 1
    fi
}

#######################################
# Step 1: Detect Package Manager
#######################################

detect_package_manager() {
    print_step "Step 1: Detecting Package Manager"

    if command_exists apt-get; then
        PKG_MANAGER="apt-get"
        INSTALL_CMD="$USE_SUDO env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get install -y"
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

    # Later steps may need packages even when all baseline commands exist.
    print_info "Updating package lists..."
    update_package_lists

    # Check and install only missing essentials
    $INSTALL_CMD ca-certificates
    install_if_missing python3 python3
    if [ "$PKG_MANAGER" = apt-get ]; then
        install_if_missing ssh-agent openssh-client
        $INSTALL_CMD python3-venv
    else
        install_if_missing ssh-agent openssh
    fi
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
    if ! git config --global user.email >/dev/null; then
        backup_file "$HOME/.gitconfig"
        git config --global user.email "${INSIS_GIT_EMAIL:-qinxun@gmail.com}"
    fi
    if ! git config --global user.name >/dev/null; then
        backup_file "$HOME/.gitconfig"
        git config --global user.name "${INSIS_GIT_NAME:-Jerry Bai}"
    fi
    print_success "Git identity configured (existing values preserved)"
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
            $INSTALL_CMD fish
            print_success "Fish installed"
        else
            print_warning "Skipping Fish installation"
        fi
    else
        print_success "Fish already installed: $(fish --version)"
    fi

    # Keep installation resumable if a previous download was interrupted.
    if [ ! -d "$HOME/.fzf" ]; then
        git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
    fi
    if [ ! -x "$HOME/.fzf/bin/fzf" ]; then
        "$HOME/.fzf/install" --bin
    fi
    export PATH="$HOME/.fzf/bin:$PATH"
    print_success "fzf available: $(fzf --version)"

    # fzf.fish's directory search and previews need fd and bat. It recognizes
    # Debian's fdfind; the shared Fish config maps bat to batcat when needed.
    if ! command_exists fd && ! command_exists fdfind; then
        case "$PKG_MANAGER" in
            apt-get|yum|dnf) $INSTALL_CMD fd-find ;;
            pacman) $INSTALL_CMD fd ;;
        esac
    fi
    if ! command_exists bat && ! command_exists batcat; then
        $INSTALL_CMD bat
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
    if ! command_exists node || [ "$(node -p 'process.versions.node.split(".")[0]')" -lt 20 ]; then
        if ask_yes_no "Install Node.js? (required for some Neovim plugins)"; then
            print_info "Installing Node.js..."
            if [ "$PKG_MANAGER" = "apt-get" ]; then
                # Use NodeSource for newer version
                local node_setup
                node_setup="$(mktemp)"
                if ! curl -fsSL https://deb.nodesource.com/setup_lts.x -o "$node_setup" ||
               ! $USE_SUDO env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l bash "$node_setup"; then
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
    print_step "Step 4: Configuring the Account Login Shell"
    if ! command_exists fish; then
        print_warning "Fish not installed, skipping"
        return 0
    fi
    local fish_path user_name current_login_shell
    fish_path="$(command -v fish)"
    user_name="$(id -un)"
    current_login_shell="$(getent passwd "$user_name" | cut -d: -f7)"
    if [ "$current_login_shell" = "$fish_path" ]; then
        print_success "Fish is already the account login shell"
        return 0
    fi
    if ask_yes_no "Set Fish as your account login shell?"; then
        if ! grep -Fxq "$fish_path" /etc/shells; then
            backup_file /etc/shells
            printf '%s\n' "$fish_path" | $USE_SUDO tee -a /etc/shells >/dev/null
        fi
        mkdir -p "$BACKUP_DIR"
        chmod 700 "$BACKUP_DIR"
        printf '%s:%s\n' "$user_name" "$current_login_shell" > "$BACKUP_DIR/login-shell.txt"
        $USE_SUDO chsh -s "$fish_path" "$user_name"
        print_success "Login shell set to Fish; reconnect or run 'exec fish'"
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

    mkdir -p "$HOME/.config/fish"
    backup_file "$HOME/.config/fish/config.fish"
    backup_file "$HOME/.config/fish/fish_plugins"

    # Install the guarded template first. Fisher stores ownership in Fish
    # universal variables; --no-config disables their persistence and makes a
    # subsequent run report its own files as conflicts.
    install_template fish_config.fish "$HOME/.config/fish/config.fish"
    if [ ! -f "$HOME/.config/fish/functions/fisher.fish" ]; then
        local fisher_bootstrap
        fisher_bootstrap="$(mktemp)"
        curl -fLSs --retry 3 https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish -o "$fisher_bootstrap"
        fish -c 'source $argv[1]; fisher install jorgebucaran/fisher' "$fisher_bootstrap"
        rm -f "$fisher_bootstrap"
    fi
    install_template fish_plugins "$HOME/.config/fish/fish_plugins"
    fish -c 'source "$HOME/.config/fish/functions/fisher.fish"; fisher update'
    print_success "Fish configuration and plugins installed"

    # cmux installs its relay and a per-workspace Fish integration on
    # `cmux ssh`. The integration reports PWD so the Files surface follows
    # navigation in the outer Fish shell. Load it additively when Fish was
    # started normally rather than through cmux's injected XDG config.
    mkdir -p ~/.config/fish/conf.d
    local cmux_fish="$HOME/.config/fish/conf.d/99-cmux.fish"
    backup_file "$cmux_fish"

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

    # cmux may explicitly launch Bash even though the account shell is Fish.
    # Wait until its injected rc file has exported the integration directory.
    # Ordinary interactive Bash sessions remain Bash.
    if [ "$(getent passwd "$(id -un)" | cut -d: -f7)" = "$(command -v fish)" ] &&
       ! grep -Fq '# insis-native-cmux-fish-v1' "$HOME/.bashrc" 2>/dev/null; then
        backup_file "$HOME/.bashrc"
        cat >> "$HOME/.bashrc" << 'EOF'

# insis-native-cmux-fish-v1
if [[ $- == *i* ]]; then
    _insis_cmux_enter_fish() {
        if [ -n "${CMUX_SHELL_INTEGRATION_DIR:-}" ] &&
           [ -r "$CMUX_SHELL_INTEGRATION_DIR/fish/config.fish" ]; then
            if [ "${XDG_CONFIG_HOME:-}" != "$CMUX_SHELL_INTEGRATION_DIR" ]; then
                export CMUX_FISH_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
                export XDG_CONFIG_HOME="$CMUX_SHELL_INTEGRATION_DIR"
            fi
            exec fish
        fi
    }
    # Preserve both string and array forms of Bash's PROMPT_COMMAND.
    if declare -p PROMPT_COMMAND 2>/dev/null | grep -q 'declare -a'; then
        if [[ " ${PROMPT_COMMAND[*]} " != *' _insis_cmux_enter_fish '* ]]; then
            PROMPT_COMMAND+=(_insis_cmux_enter_fish)
        fi
    else
        case ";${PROMPT_COMMAND:-};" in
            *';_insis_cmux_enter_fish;'*) ;;
            *) PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_insis_cmux_enter_fish" ;;
        esac
    fi
fi
EOF
    fi
}

#######################################
# Step 6: Setup tmux Configuration
#######################################

setup_tmux() {
    print_step "Step 6: Configuring tmux with OSC 52 Support"

    local tmp_file
    tmp_file="$(mktemp)"
    if ! fetch_template tmux.conf "$tmp_file"; then
        rm -f "$tmp_file"
        return 1
    fi
    if command_exists fish; then
        printf '\n# Use Fish for new tmux panes\nset-option -g default-shell "%s"\n' "$(command -v fish)" >> "$tmp_file"
    fi
    if ! cmp -s "$tmp_file" "$HOME/.tmux.conf"; then
        backup_file "$HOME/.tmux.conf"
        install -m 644 "$tmp_file" "$HOME/.tmux.conf"
    fi
    rm -f "$tmp_file"
    print_success "tmux configuration installed"

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

install_tmux_plugins() (
    print_step "Step 6b: Installing tmux Plugins"
    # TPM uses the current server's environment. Use a separate socket so an
    # existing user's sessions and options are never changed during setup.
    local server="insis-setup-$$" socket
    trap 'tmux -L "$server" kill-server 2>/dev/null || true' EXIT
    tmux -L "$server" -f "$HOME/.tmux.conf" new-session -d -s setup 'sleep 600'
    socket="$(tmux -L "$server" display-message -p '#{socket_path}')"
    TMUX="$socket,0,0" "$HOME/.tmux/plugins/tpm/bin/install_plugins"
    print_success "tmux plugins installed"
)

#######################################
# Step 7: Install Neovim
#######################################

install_neovim() {
    print_step "Step 7: Installing Neovim $NEOVIM_VERSION"

    if command_exists nvim; then
        CURRENT_VERSION=$(nvim --version | sed -n '1p')
        print_success "Neovim already installed: $CURRENT_VERSION"
        # -y installs missing tools; it never forces a downgrade/reinstall.
        if [ "$AUTO_YES" = true ] || ! ask_yes_no "Reinstall Neovim $NEOVIM_VERSION?"; then
            return 0
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
        return 1
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

    print_success "Neovim $NEOVIM_VERSION installed: $(nvim --version | sed -n '1p')"
}

#######################################
# Step 8: Setup Neovim Configuration
#######################################

setup_neovim_config() {
    print_step "Step 8: Setting up Neovim Configuration"
    local config_dir="$HOME/.config/nvim" clone_dir
    if [ -e "$config_dir" ]; then
        print_success "Existing Neovim configuration preserved: $config_dir"
        return 0
    fi
    mkdir -p "$HOME/.config"
    clone_dir="$(mktemp -d "$HOME/.config/.insis-nvim.XXXXXX")"
    if ! git clone --branch "$NVIM_CONFIG_BRANCH" --single-branch \
        "https://github.com/$(repo_path).git" "$clone_dir"; then
        rm -rf "$clone_dir"
        print_error "Neovim config clone failed"
        return 1
    fi
    mv "$clone_dir" "$config_dir"
    print_success "Neovim config cloned (branch: $NVIM_CONFIG_BRANCH)"
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

install_neovim_language_tools() {
    print_step "Step 8c: Installing Neovim Language Tools"
    if [ ! -f "$HOME/.config/nvim/lua/insis/env/init.lua" ]; then
        print_warning "Existing config is not InsisVim; leaving its language tools unchanged"
        return 0
    fi
    local bootstrap
    bootstrap="$(mktemp --suffix=.lua)"
    cat > "$bootstrap" <<'LUA'
local ok, err = pcall(function()
    local env = require("insis.env")
    local registry = require("mason-registry")
    local mapping = require("mason-lspconfig.mappings.server").lspconfig_to_package
    registry.refresh()
    local packages = {}
    for _, name in ipairs(env.getLSPEnsureList()) do
        packages[#packages + 1] = registry.get_package(assert(mapping[name], name))
    end
    for _, name in ipairs(env.getToolEnsureList()) do
        packages[#packages + 1] = registry.get_package(type(name) == "table" and name[1] or name)
    end
    local handles = {}
    for _, package in ipairs(packages) do
        if not package:is_installed() then handles[#handles + 1] = package:install() end
    end
    local languages = env.getTSEnsureList()
    -- InsisVim's treesitter.setup() already queued these installs during init.
    -- Starting them again races over the same clone directories and Git locks.
    -- Await the startup jobs below instead of creating a second installer.
    local parser_dir = assert(require("nvim-treesitter.configs").get_parser_install_dir())
    local missing = {}
    local ready = vim.wait(300000, function()
        missing = {}
        for _, package in ipairs(packages) do
            -- Mason's is_installed() schedules cache invalidation; calling it
            -- in vim.wait's predicate can spin the event loop on Neovim 0.9.
            if not vim.loop.fs_stat(package:get_install_path() .. "/mason-receipt.json") then
                missing[#missing + 1] = package.name
            end
        end
        for _, language in ipairs(languages) do
            -- Neovim's bundled parsers can satisfy has_parser() before the
            -- plugin's own download/compile finishes (notably for Lua).
            if not vim.loop.fs_stat(parser_dir .. "/" .. language .. ".so")
                or not require("nvim-treesitter.parsers").has_parser(language) then
                missing[#missing + 1] = "parser:" .. language
            end
        end
        for _, handle in ipairs(handles) do
            if not handle:is_closed() then missing[#missing + 1] = "pending installer" end
        end
        return #missing == 0
    end, 250)
    assert(ready, "Language tools not installed: " .. table.concat(missing, ", "))
end)
if not ok then
    vim.api.nvim_err_writeln(tostring(err))
    vim.cmd("cquit 1")
end
LUA
    # Commands run before VimEnter: start Mason's installers explicitly, but
    # only await Tree-sitter's jobs, which were already queued during init.
    if ! timeout --kill-after=5s 360s nvim --headless "+luafile $bootstrap" +qa; then
        rm -f "$bootstrap"
        print_error "Neovim language tool installation failed; see :MasonLog"
        return 1
    fi
    rm -f "$bootstrap"
    print_success "Configured language servers, formatters and parsers are ready"
}

#######################################
# Step 9: Install Additional Tools
#######################################

setup_claude_settings() {
    local target="$HOME/.claude/settings.json" tmp_file
    if [ ! -f "$target" ]; then
        install_template claude_settings.json "$target" 600
        return 0
    fi
    # Keep credentials, model providers, existing hooks, and editor preferences.
    tmp_file="$(mktemp)"
    if ! jq '
        .env = (.env // {})
        | .env.EDITOR = (.env.EDITOR // "nvim-prompt-editor")
        | .env.VISUAL = (.env.VISUAL // "nvim-prompt-editor")
    ' "$target" > "$tmp_file"; then
        rm -f "$tmp_file"
        print_error "Invalid Claude settings; leaving them unchanged"
        return 1
    fi
    if ! cmp -s "$tmp_file" "$target"; then
        backup_file "$target"
        install -m 600 "$tmp_file" "$target"
    fi
    rm -f "$tmp_file"
    print_success "Claude prompt editor configured (existing settings preserved)"
}

setup_codex_agents() {
    local target="$HOME/.codex/AGENTS.md"
    if [ -f "$target" ]; then
        print_success "Codex instructions already exist, leaving unchanged"
        return 0
    fi
    install_template AGENTS.md "$target" 600
    print_success "Codex instructions installed"
}

ensure_uv() {
    if command_exists uv; then
        print_success "uv already available: $(uv --version)"
        return 0
    fi

    local installer
    installer="$(mktemp)"

    print_info "Installing uv from the official Astral installer..."
    if ! curl -LsSf https://astral.sh/uv/install.sh -o "$installer" ||
       ! UV_NO_MODIFY_PATH=1 UV_INSTALL_DIR="$HOME/.local/bin" sh "$installer"; then
        rm -f "$installer"
        print_error "uv installation failed"
        return 1
    fi
    rm -f "$installer"

    export PATH="$HOME/.local/bin:$PATH"
    hash -r
    if ! command_exists uv; then
        print_error "uv was installed but is not available on PATH"
        return 1
    fi

    print_success "uv installed: $(uv --version)"
}

ensure_local_bin_in_fish() {
    if command_exists fish; then
        if fish -c 'fish_add_path $HOME/.local/bin; contains -- "$HOME/.local/bin" $PATH' 2>/dev/null; then
            print_success "$HOME/.local/bin is available in Fish"
        else
            print_warning "Could not persist ~/.local/bin in Fish PATH"
        fi
    fi
}

verify_magic_wormhole() {
    local version

    if ! command_exists wormhole; then
        print_error "wormhole is not available on PATH"
        return 1
    fi
    if ! version="$(wormhole --version 2>&1)"; then
        print_error "wormhole exists but failed its version check"
        return 1
    fi

    version="${version%%$'\n'*}"
    print_success "Magic Wormhole available: $version"
}

install_magic_wormhole() {
    if command_exists wormhole || [ -x "$HOME/.local/bin/wormhole" ]; then
        export PATH="$HOME/.local/bin:$PATH"
        ensure_local_bin_in_fish
        verify_magic_wormhole
        return
    fi

    if ! ask_yes_no "Install Magic Wormhole with uv tool?"; then
        print_warning "Skipping Magic Wormhole"
        return 0
    fi

    ensure_uv
    ensure_local_bin_in_fish

    print_info "Installing Magic Wormhole with uv tool..."
    if ! uv tool install magic-wormhole; then
        print_error "Magic Wormhole installation failed"
        return 1
    fi

    export PATH="$HOME/.local/bin:$PATH"
    hash -r
    verify_magic_wormhole
}

install_additional_tools() {
    print_step "Step 9: Installing Additional LSPs/Formatters (Optional)"

    if ask_yes_no "Install Python LSP and Black in isolated uv tool environments?"; then
        ensure_uv
        uv tool install python-lsp-server
        uv tool install black
        print_success "Python LSP and Black installed without modifying system Python"
    fi

    # Magic Wormhole (isolated CLI installation managed by uv)
    install_magic_wormhole

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

    if command_exists codex; then
        setup_codex_agents
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
        cat > "$config" << EOF
$notify_line

[tui]
alternate_screen = "never"
EOF
        chmod 600 "$config"
        print_success "Codex cmux notification and terminal scrollback configured"
        return 0
    fi

    # Parse before merging. Only add absent values and preserve the original
    # text, including comments, credentials, custom providers and TUI settings.
    tmp_file="$(mktemp)"
    if ! python3 - "$config" "$notify_script" "$tmp_file" <<'PYCODE'
import json
import re
import sys
import tomllib
from pathlib import Path

config, notifier, output = map(Path, sys.argv[1:])
text = config.read_text()
data = tomllib.loads(text)
if "notify" not in data:
    text = "notify = " + json.dumps([str(notifier)]) + "\n\n" + text
if "alternate_screen" not in data.get("tui", {}):
    section = re.search(r'^\s*\[\s*(?:tui|"tui"|\'tui\')\s*\][ \t]*(?:#[^\n]*)?$', text, re.M)
    if section:
        text = text[:section.end()] + '\nalternate_screen = "never"' + text[section.end():]
    elif "tui" not in data:
        text = text.rstrip() + '\n\n[tui]\nalternate_screen = "never"\n'
    # Unusual inline/dotted TUI tables are deliberately left intact.
tomllib.loads(text)
output.write_text(text)
PYCODE
    then
        rm -f "$tmp_file"
        print_error "Cannot parse/merge Codex TOML (Python 3.11+ required); existing file preserved"
        return 1
    fi
    if ! cmp -s "$tmp_file" "$config"; then
        backup_file "$config"
        install -m 600 "$tmp_file" "$config"
    fi
    rm -f "$tmp_file"
    print_success "Codex notifications and scrollback configured (existing values preserved)"
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

    # mdprev 0.1.1 has no --host option and calls server.listen(port), which
    # exposes documents on every interface. Scope this preload to mdview's
    # Node processes and supply loopback for the package's hostless call.
    local loopback_guard="$HOME/.local/lib/insis-mdview/loopback.cjs"
    mkdir -p "$(dirname "$loopback_guard")"
    if [ ! -e "$loopback_guard" ]; then
        cat > "$loopback_guard" <<'JS'
const net = require('node:net');
const listen = net.Server.prototype.listen;
net.Server.prototype.listen = function (...args) {
  if ((typeof args[0] === 'number' || /^\d+$/.test(args[0])) &&
      (args.length === 1 || typeof args[1] === 'function')) {
    args.splice(1, 0, '127.0.0.1');
  }
  return listen.apply(this, args);
};
JS
        chmod 644 "$loopback_guard"
    fi

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

    set -l loopback_guard "$HOME/.local/lib/insis-mdview/loopback.cjs"
    if not test -r "$loopback_guard"
        echo "mdview: missing loopback guard; rerun setup_remote_linux.sh"
        return 1
    end
    set -l node_options "$NODE_OPTIONS --require=\"$loopback_guard\""
    command nohup env NODE_OPTIONS="$node_options" npx --yes @hypersoweak/mdprev@0.1.1 "$file" \
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

    # Populate the pinned npx cache now, rather than during the first preview.
    npx --yes "@hypersoweak/mdprev@$MDPREV_VERSION" --version
}

#######################################
# Main Setup Function
#######################################

main() {
    print_info "This script will set up your native Linux development environment"
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
    setup_prompt_editor
    setup_tmux
    install_tmux_plugins
    install_neovim
    setup_neovim_config
    install_additional_tools
    install_neovim_plugins
    install_neovim_language_tools
    setup_cmux_phase_a_integration
    setup_mdview_helpers

    # Print summary
    print_step "Setup Complete!"

    print_success "Your native Linux development environment is now configured!"
    echo ""
    print_info "Next steps:"
    echo "  1. From the Mac, connect with: cmux ssh <host> --name <project>"
    echo "  2. Run 'exec fish' in this existing connection, or reconnect to enter Fish automatically"
    echo "  3. From Fish, start/attach tmux: tmux new-session -A -s <session>"
    echo "  4. tmux and Neovim plugins are already installed"
    echo "  5. Start neovim / Claude Code / Codex inside tmux"
    echo "  6. In nvim, run: :checkhealth provider"
    echo ""
    print_info "cmux Phase A checks (after connecting from cmux):"
    echo "  - command -v cmux should resolve to $HOME/.cmux/bin/cmux"
    echo "  - cmux ping should return { \"pong\": true }"
    echo "  - Claude Stop/Task and Codex turn-complete notifications should appear in cmux"
    echo "  - mdview <file.md> [port] uses @hypersoweak/mdprev@$MDPREV_VERSION"
    echo "  - Open http://localhost:<port> in the Browser surface; use an SSH tunnel outside cmux"
    echo ""
    print_info "Test clipboard integration:"
    echo "  - In remote nvim, select text and press <C-c>"
    echo "  - On local macOS, press Cmd+V to paste"
    echo ""
    print_warning "Phase A transport is cmux ssh + remote tmux. Mosh is intentionally not required."
    print_info "Original files are backed up under: $BACKUP_DIR"
    print_success "Happy coding!"
}

# Run main function when executed directly (allows sourcing for tests/debugging)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    while getopts ":yh" opt; do
        case "$opt" in
            y) AUTO_YES=true ;;
            h) echo "Usage: $0 [-y] (run as the account to configure)"; exit 0 ;;
            *) echo "Usage: $0 [-y]" >&2; exit 2 ;;
        esac
    done
    shift "$((OPTIND - 1))"
    if [ "$#" -ne 0 ]; then
        echo "Unexpected arguments: $*" >&2
        exit 2
    fi
    main
fi
