#!/usr/bin/env bash

# Terminate already running bar instances
killall -q polybar

# Wait until the processes have been shut down
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done

# Launch bars
echo "---" | tee -a /tmp/polybar-main.log /tmp/polybar-portrait.log
polybar main 2>&1 | tee -a /tmp/polybar-main.log & disown
polybar portrait 2>&1 | tee -a /tmp/polybar-portrait.log & disown

echo "Polybar launched..."
