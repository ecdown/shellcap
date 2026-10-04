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
sed -i "1s|^#!.*python.*|#!$PYTHON|" "$PREFIX_LIB/shellcap_log.py"
sed -i "1s|^#!.*python.*|#!$PYTHON|" "$PREFIX_BIN/shellcap-query"

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

echo "Installation complete!"
echo "Database will be stored at: $HOME/.local/share/shellcap/shellcap.db"
echo "Start a new shell session to begin logging."
