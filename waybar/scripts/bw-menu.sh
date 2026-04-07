#!/bin/bash

set -euo pipefail

# Bitwarden vault popup for waybar — launches GTK popup via rbw.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POPUP_SCRIPT="$SCRIPT_DIR/bw-popup.py"

# Ensure rbw is installed
if ! command -v rbw &>/dev/null; then
    notify-send -u critical "Bitwarden" "rbw is not installed"
    exit 1
fi

# Ensure vault is unlocked (silent exit if user cancels pinentry)
if ! rbw unlocked 2>/dev/null; then
    rbw unlock || exit 0
fi

# Background sync
rbw sync &

# Launch the popup
python3 "$POPUP_SCRIPT"
