#!/bin/bash
set -e

# Find Python executable
PYTHON=""
if command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON="python"
else
  echo "Error: Python 3 is required but not found in PATH"
  exit 1
fi

echo "Using Python: $PYTHON ($($PYTHON --version 2>&1))"

# Portable in-place sed (GNU sed: -i, BSD/macOS sed: -i '')
sed_inplace() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

# Check for sqlite3 availability (CLI) - optional, we use Python's sqlite3
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "Warning: sqlite3 CLI not found. Queries can still be made via 'shellcap-query' or Python."
else
  echo "sqlite3 CLI found: $(sqlite3 --version)"
fi

PREFIX_CONFIG="$HOME/.config/shellcap"
PREFIX_LIB="$HOME/.local/lib/shellcap"
PREFIX_BIN="$HOME/.local/bin"
PREFIX_SHARE="$HOME/.local/share/shellcap"

mkdir -p "$PREFIX_CONFIG" "$PREFIX_LIB" "$PREFIX_BIN" "$PREFIX_SHARE"

# Copy files
cp shellcap.env "$PREFIX_CONFIG/"
cp shellcap.bash.inc "$PREFIX_CONFIG/"
cp shellcap.zsh "$PREFIX_CONFIG/"
cp shellcap_log.py "$PREFIX_LIB/"
cp shellcap-query "$PREFIX_BIN/"

chmod +x "$PREFIX_LIB/shellcap_log.py"
chmod +x "$PREFIX_BIN/shellcap-query"

# Update shebangs to use detected Python
sed_inplace "1s|^#!.*python.*|#!/usr/bin/env $PYTHON|" "$PREFIX_LIB/shellcap_log.py"
sed_inplace "1s|^#!.*python.*|#!/usr/bin/env $PYTHON|" "$PREFIX_BIN/shellcap-query"

# Install bash integration if not present
if [ -f "$HOME/.bashrc" ]; then
  if ! grep -q "shellcap.bash" "$HOME/.bashrc" 2>/dev/null; then
    echo '
# shellcap logging
if [ -f ~/.config/shellcap/shellcap.bash ]; then
  . ~/.config/shellcap/shellcap.bash
fi' >> "$HOME/.bashrc"
    echo "Added shellcap to ~/.bashrc"
  fi
fi

# Create shellcap.bash loader
cat > "$PREFIX_CONFIG/shellcap.bash" << 'BSH'
# shellcap bash integration
[ -f "$HOME/.config/shellcap/shellcap.env" ] && . "$HOME/.config/shellcap/shellcap.env"
if [ -f "$HOME/.config/shellcap/shellcap.bash.inc" ]; then
  . "$HOME/.config/shellcap/shellcap.bash.inc"
fi
BSH

# Ensure .bash_profile sources .bashrc if needed
if [ -f "$HOME/.bash_profile" ]; then
  if ! grep -q "bashrc" "$HOME/.bash_profile" 2>/dev/null; then
    echo '
if [ -f ~/.bashrc ]; then
  . ~/.bashrc
fi' >> "$HOME/.bash_profile"
  fi
fi

# Note for zsh
if [ -f "$HOME/.zshrc" ]; then
  if ! grep -q "shellcap.zsh" "$HOME/.zshrc" 2>/dev/null; then
    echo '
# shellcap logging
if [ -f ~/.config/shellcap/shellcap.zsh ]; then
  . ~/.config/shellcap/shellcap.zsh
fi' >> "$HOME/.zshrc"
    echo "Added shellcap to ~/.zshrc"
  fi
else
  echo "Note: Add 'source ~/.config/shellcap/shellcap.zsh' to your ~/.zshrc if using zsh"
fi

# Install pause/unpause scripts
cp shellcap-pause "$PREFIX_BIN/" 2>/dev/null || true
cp shellcap-unpause "$PREFIX_BIN/" 2>/dev/null || true
cp shellcap-status "$PREFIX_BIN/" 2>/dev/null || true
cp shellcap "$PREFIX_BIN/" 2>/dev/null || true

chmod +x "$PREFIX_BIN/shellcap-pause" 2>/dev/null || true
chmod +x "$PREFIX_BIN/shellcap-unpause" 2>/dev/null || true
chmod +x "$PREFIX_BIN/shellcap-status" 2>/dev/null || true
chmod +x "$PREFIX_BIN/shellcap" 2>/dev/null || true

# Update shebangs if needed
sed_inplace "1s|^#!.*bash.*|#!/usr/bin/env bash|" "$PREFIX_BIN/shellcap-pause" 2>/dev/null || true
sed_inplace "1s|^#!.*bash.*|#!/usr/bin/env bash|" "$PREFIX_BIN/shellcap-unpause" 2>/dev/null || true
sed_inplace "1s|^#!.*bash.*|#!/usr/bin/env bash|" "$PREFIX_BIN/shellcap-status" 2>/dev/null || true
sed_inplace "1s|^#!.*bash.*|#!/usr/bin/env bash|" "$PREFIX_BIN/shellcap" 2>/dev/null || true
cp shellcap-state "$PREFIX_BIN/" 2>/dev/null || true
chmod +x "$PREFIX_BIN/shellcap-state" 2>/dev/null || true
sed_inplace "1s|^#!.*bash.*|#!/usr/bin/env bash|" "$PREFIX_BIN/shellcap-state" 2>/dev/null || true

# Ensure ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  added_path=false
  # Try zshrc first (default on macOS)
  if [ -f "$HOME/.zshrc" ]; then
    if ! grep -q '\$HOME/\.local/bin\|~/.local/bin' "$HOME/.zshrc" 2>/dev/null; then
      echo '
# Add ~/.local/bin to PATH for shellcap
export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
      echo "Added ~/.local/bin to PATH in ~/.zshrc"
      added_path=true
    fi
  fi
  # Try bashrc
  if [ -f "$HOME/.bashrc" ]; then
    if ! grep -q '\$HOME/\.local/bin\|~/.local/bin' "$HOME/.bashrc" 2>/dev/null; then
      echo '
# Add ~/.local/bin to PATH for shellcap
export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
      echo "Added ~/.local/bin to PATH in ~/.bashrc"
      added_path=true
    fi
  fi
  # Fallback to bash_profile if no bashrc
  if [ ! -f "$HOME/.bashrc" ] && [ -f "$HOME/.bash_profile" ]; then
    if ! grep -q '\$HOME/\.local/bin\|~/.local/bin' "$HOME/.bash_profile" 2>/dev/null; then
      echo '
# Add ~/.local/bin to PATH for shellcap
export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bash_profile"
      echo "Added ~/.local/bin to PATH in ~/.bash_profile"
      added_path=true
    fi
  fi
  if [ "$added_path" = false ]; then
    echo "Note: ~/.local/bin is not in your PATH. Add 'export PATH=\"\$HOME/.local/bin:\$PATH\"' to your shell rc file."
  fi
fi

echo "Installation complete!"
echo "Database will be stored at: $HOME/.local/share/shellcap/shellcap.db"
echo "Start a new shell session to begin logging."
