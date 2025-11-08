#!/usr/bin/env bash

set -e

INSTALL_DIR="/usr/local/bin"
SCRIPT_URL="https://raw.githubusercontent.com/ayanrajpoot10/ghbin/main/ghbin.sh"
SCRIPT_NAME="ghbin"

echo "Installing ghbin"
echo ""

# Check for dependencies
echo "Checking dependencies..."
missing_deps=()

for cmd in curl jq bash; do
  if ! command -v "$cmd" &>/dev/null; then
    missing_deps+=("$cmd")
  fi
done

if [ ${#missing_deps[@]} -ne 0 ]; then
  echo "Missing dependencies: ${missing_deps[*]}"
  echo ""
  echo "Please install them first:"
  echo "  Ubuntu/Debian: sudo apt-get install ${missing_deps[*]}"
  echo "  CentOS/RHEL:   sudo yum install ${missing_deps[*]}"
  echo "  Arch Linux:    sudo pacman -S ${missing_deps[*]}"
  echo "  macOS:         brew install ${missing_deps[*]}"
  exit 1
fi

echo "All dependencies found"
echo ""

# Determine if we need sudo
need_sudo=false
if [ ! -w "$INSTALL_DIR" ]; then
  need_sudo=true
  echo "$INSTALL_DIR is not writable, will use sudo"
fi

# Download script
echo "Downloading ghbin..."
temp_file=$(mktemp)
if curl -sSL "$SCRIPT_URL" -o "$temp_file"; then
  chmod +x "$temp_file"
else
  echo "Failed to download ghbin"
  rm -f "$temp_file"
  exit 1
fi

# Install
echo "Installing to $INSTALL_DIR..."
if [ "$need_sudo" = true ]; then
  sudo mv "$temp_file" "$INSTALL_DIR/$SCRIPT_NAME"
else
  mv "$temp_file" "$INSTALL_DIR/$SCRIPT_NAME"
fi

echo ""
echo "ghbin installed successfully!"
echo ""

# Check if ~/.local/bin is in PATH (where packages will be installed by default)
LOCAL_BIN_DIR="${HOME}/.local/bin"
if [[ ":$PATH:" != *":$LOCAL_BIN_DIR:"* ]]; then
  echo "Important: Packages install to ~/.local/bin by default"
  echo ""
  echo "Add ~/.local/bin to your PATH by running:"
  echo ""

  # Detect shell and provide appropriate instructions
  if [[ "$SHELL" == *"zsh"* ]] || [[ -f "${HOME}/.zshrc" ]]; then
    echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
    echo "  source ~/.zshrc"
  elif [[ "$SHELL" == *"bash"* ]] || [[ -f "${HOME}/.bashrc" ]]; then
    echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
    echo "  source ~/.bashrc"
  else
    echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.profile"
    echo "  source ~/.profile"
  fi
  echo ""
else
  echo "~/.local/bin is already in your PATH"
  echo ""
fi

echo "Usage:"
echo "  ghbin install owner/repo    # Install package to ~/.local/bin (no sudo)"
echo "  ghbin list                  # List installed packages"
echo "  ghbin help                  # Show help"
echo ""
echo "Try: ghbin install cli/cli"
