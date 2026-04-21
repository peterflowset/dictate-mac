#!/usr/bin/env bash
set -e

# ── Dictate-Mac installer ────────────────────────────────────────────────────
# Sets up Python venv, launcher script, and optional login item.
# Must be run from the project root.

if [[ "$OSTYPE" != "darwin"* ]]; then
  echo "macOS only."
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "python3 not found. Install it (e.g. via Homebrew: brew install python)"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/venv"
LAUNCHER="$HOME/Applications/dictate.command"

echo "▶ Creating Python venv at $VENV_DIR"
python3 -m venv "$VENV_DIR"

echo "▶ Installing dependencies"
"$VENV_DIR/bin/pip" install --quiet --upgrade pip
"$VENV_DIR/bin/pip" install --quiet -r "$SCRIPT_DIR/requirements.txt"

# Determine real Python binary for the Accessibility permission instructions
REAL_PYTHON_APP="$("$VENV_DIR/bin/python" -c "
import os, sys
real = os.path.realpath(sys.executable)
version_dir = os.path.dirname(os.path.dirname(real))
print(os.path.join(version_dir, 'Resources', 'Python.app', 'Contents', 'MacOS'))
")"

# GROQ_API_KEY
if [ -z "${GROQ_API_KEY:-}" ]; then
  echo ""
  echo "▶ You need a free Groq API key: https://console.groq.com/keys"
  read -r -p "   Paste key: " GROQ_API_KEY
fi

echo ""
read -r -p "▶ Persist GROQ_API_KEY to ~/.zshrc? [Y/n] " reply
reply=${reply:-Y}
if [[ "$reply" =~ ^[Yy] ]]; then
  if ! grep -q "^export GROQ_API_KEY=" "$HOME/.zshrc" 2>/dev/null; then
    echo "export GROQ_API_KEY=\"$GROQ_API_KEY\"" >> "$HOME/.zshrc"
    echo "  ✓ Added to ~/.zshrc"
  else
    echo "  ℹ GROQ_API_KEY already present in ~/.zshrc (not overwritten)"
  fi
fi

# Launcher
mkdir -p "$HOME/Applications"
cat > "$LAUNCHER" <<EOF
#!/bin/bash
# Dictate launcher — started by Terminal.app so it inherits accessibility permission
export GROQ_API_KEY="\${GROQ_API_KEY:-$GROQ_API_KEY}"
pkill -f "dictate.py" 2>/dev/null
sleep 0.5
exec "$VENV_DIR/bin/python" -u "$SCRIPT_DIR/dictate.py"
EOF
chmod +x "$LAUNCHER"
echo "▶ Launcher written to $LAUNCHER"

# Optional login item
read -r -p "▶ Auto-start on login? [Y/n] " reply
reply=${reply:-Y}
if [[ "$reply" =~ ^[Yy] ]]; then
  osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$LAUNCHER\", hidden:false}" >/dev/null
  echo "  ✓ Login item added"
fi

# Ad-hoc sign Homebrew Python to improve TCC reliability
if [[ "$REAL_PYTHON_APP" == /opt/homebrew/* || "$REAL_PYTHON_APP" == /usr/local/* ]]; then
  echo "▶ Ad-hoc code-signing Python.app (helps with macOS Accessibility TCC)"
  codesign --force --deep --sign - "$(dirname "$REAL_PYTHON_APP")/.." 2>&1 | tail -1 || true
fi

cat <<EOF

─────────────────────────────────────────────────────────────────────
 ✓ Install complete.

 ONE MANUAL STEP IS REQUIRED:

   Grant Accessibility permission to the Python binary.

   1. System Settings → Privacy & Security → Accessibility
   2. Click  +  → Cmd+Shift+G → paste this path:
      $REAL_PYTHON_APP
   3. Select the  Python  file → click Open → toggle ON

 Then start Dictate:

   open "$LAUNCHER"

 (or drag dictate.command into your Dock for one-click start)

 Press and hold  Option (⌥)  anywhere → speak → release → text pastes.
─────────────────────────────────────────────────────────────────────

EOF
