#!/bin/bash
# Quick Setup Script for Mac Mini
# Run this script on your Mac Mini to automate the installation

set -e  # Exit on error

echo "==================================="
echo "Mac Development Environment Setup"
echo "==================================="
echo ""

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "📦 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    echo "✅ Homebrew already installed"
fi

echo ""
echo "📦 Installing packages..."

# Install all tools
brew install --cask alacritty
brew install --cask karabiner-elements
brew install fish fzf ripgrep tmux neovim git node bat eza fd

echo ""
echo "🐚 Setting up Fish shell..."

# Add fish to allowed shells
if ! grep -q "/opt/homebrew/bin/fish" /etc/shells; then
    echo /opt/homebrew/bin/fish | sudo tee -a /etc/shells
fi

# Set fish as default shell
if [ "$SHELL" != "/opt/homebrew/bin/fish" ]; then
    chsh -s /opt/homebrew/bin/fish
    echo "⚠️  You'll need to log out and back in for Fish to be the default shell"
fi

# Install Fisher
echo ""
echo "🎣 Installing Fisher (Fish plugin manager)..."
fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher"

# Install Fish plugins
echo "🔌 Installing Fish plugins..."
fish -c "fisher install PatrickF1/fzf.fish"
fish -c "fisher install jethrokuan/z"

# Create config directories
echo ""
echo "📁 Creating config directories..."
mkdir -p ~/.config/{alacritty,fish,nvim,karabiner}

echo ""
echo "✅ Base installation complete!"
echo ""
echo "==================================="
echo "Next Steps:"
echo "==================================="
echo "1. Copy your config files from MacBook:"
echo "   - ~/.config/alacritty/"
echo "   - ~/.config/fish/"
echo "   - ~/.config/nvim/"
echo "   - ~/.config/karabiner/"
echo ""
echo "2. Or use scp from Mac Mini:"
echo "   scp -r username@macbook-ip:~/.config/alacritty ~/.config/"
echo "   scp -r username@macbook-ip:~/.config/fish ~/.config/"
echo "   scp -r username@macbook-ip:~/.config/nvim ~/.config/"
echo "   scp -r username@macbook-ip:~/.config/karabiner ~/.config/"
echo ""
echo "3. Switch to newton_stable branch in nvim config:"
echo "   cd ~/.config/nvim && git checkout newton_stable"
echo ""
echo "4. Launch nvim to install plugins:"
echo "   nvim"
echo ""
echo "5. Grant Karabiner-Elements permissions in System Settings"
echo ""
echo "==================================="
