#!/bin/zsh
# Captures one clean simulator screen for the App Store screenshots.
#   marketing/screenshots/capture.sh <lang> <name>     → raw/<lang>/<name>.png
# Status bar: 9:41, full battery and signal (Apple's marketing look).
set -euo pipefail
SIM=${METLY_SIM_UDID:-5EDB177C-B727-4874-9FA0-E6295FC00B83}
DIR="$(cd "$(dirname "$0")" && pwd)/raw/$1"
mkdir -p "$DIR"
xcrun simctl status_bar "$SIM" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100 >/dev/null
xcrun simctl io "$SIM" screenshot --type=png "$DIR/$2.png" >/dev/null 2>&1
echo "$DIR/$2.png"
