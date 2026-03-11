#!/bin/bash
mem_usage=$(free | grep Mem | awk '{printf "%.0f", ($3/$2) * 100}')
printf "RAM %02d%%" "$mem_usage"
