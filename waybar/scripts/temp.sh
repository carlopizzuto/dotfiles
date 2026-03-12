#!/bin/bash

# Get CPU temp (AMD Ryzen)
cpu_temp=$(sensors | grep "Tctl" | awk '{print $2}' | sed 's/+//;s/°C//')

# Get GPU temp (NVIDIA)
gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null)

# Format output
if [ -n "$cpu_temp" ] && [ -n "$gpu_temp" ]; then
    echo "CPU ${cpu_temp}°C GPU ${gpu_temp}°C"
elif [ -n "$cpu_temp" ]; then
    echo "CPU ${cpu_temp}°C"
elif [ -n "$gpu_temp" ]; then
    echo "GPU ${gpu_temp}°C"
else
    echo "N/A"
fi
