#!/bin/bash
cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
cpu_temp=$(sensors | grep "Tctl" | awk '{print $2}' | sed 's/+//;s/°C//')
printf "C: %02.0f%% · %.1f°C" "$cpu_usage" "$cpu_temp"
