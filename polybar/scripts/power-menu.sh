#!/bin/bash

set -euo pipefail

# Power menu for polybar — GTK popup with countdown for power actions.
# Format: Label|Command|countdown (yes/no)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COUNTDOWN_SCRIPT="$SCRIPT_DIR/power-countdown.py"
POPUP_SCRIPT="$SCRIPT_DIR/power-popup.py"
COUNTDOWN_SECS=60

ENTRIES=$(
  cat <<'EOF'
Sound Settings|pavucontrol|no
Bluetooth Settings|blueman-manager|no
Restart|systemctl reboot|yes
Shutdown|systemctl poweroff|yes
Logout|i3-msg exit|yes
EOF
)

LABELS="$(printf "%s\n" "$ENTRIES" | cut -d'|' -f1)"

choice="$(printf "%s\n" "$LABELS" | python3 "$POPUP_SCRIPT")" || exit 0

[ -z "${choice:-}" ] && exit 0

cmd="$(printf "%s\n" "$ENTRIES" | awk -F'|' -v c="$choice" '$1==c {print $2; exit}')"
needs_countdown="$(printf "%s\n" "$ENTRIES" | awk -F'|' -v c="$choice" '$1==c {print $3; exit}')"

[ -z "${cmd:-}" ] && exit 0

if [ "$needs_countdown" = "yes" ]; then
    python3 "$COUNTDOWN_SCRIPT" "$choice" "$cmd" "$COUNTDOWN_SECS"
else
    nohup bash -lc "$cmd" >/dev/null 2>&1 &
fi
