#!/bin/bash
gpu_usage=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null)
gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null)
if [ -n "$gpu_usage" ] && [ -n "$gpu_temp" ]; then
    printf "G: %02d%% · %d°C" "$gpu_usage" "$gpu_temp"
else
    echo "G: N/A"
fi
