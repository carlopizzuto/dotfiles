#!/bin/bash

set -euo pipefail

# Power menu for polybar — rofi dropdown with countdown for power actions.
# Format: Label|Command|countdown (yes/no)

COUNTDOWN_SCRIPT="$HOME/.config/polybar/scripts/power-countdown.py"
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

THEME_STR='
* {
  font: "Iosevka Nerd Font 12";
}

window {
  background-color: #282828;
  border: 1px;
  border-color: #504945;
  width: 220px;
  padding: 5px;
  location: northeast;
  anchor: northeast;
  x-offset: -10;
  y-offset: 10;
}

listview {
  background-color: #282828;
  lines: 5;
  fixed-height: true;
  dynamic: false;
  spacing: 4px;
  scrollbar: false;
}

element {
  background-color: #282828;
  text-color: #ebdbb2;
  padding: 6px 8px;
}

element selected {
  background-color: #3c3836;
  text-color: #fabd2f;
}

inputbar {
  enabled: false;
}
'

choice="$(
  printf "%s\n" "$LABELS" | rofi -dmenu \
    -no-config \
    -theme-str "$THEME_STR"
)" || exit 0

[ -z "${choice:-}" ] && exit 0

cmd="$(printf "%s\n" "$ENTRIES" | awk -F'|' -v c="$choice" '$1==c {print $2; exit}')"
needs_countdown="$(printf "%s\n" "$ENTRIES" | awk -F'|' -v c="$choice" '$1==c {print $3; exit}')"

[ -z "${cmd:-}" ] && exit 0

if [ "$needs_countdown" = "yes" ]; then
    python3 "$COUNTDOWN_SCRIPT" "$choice" "$cmd" "$COUNTDOWN_SECS"
else
    nohup bash -lc "$cmd" >/dev/null 2>&1 &
fi
