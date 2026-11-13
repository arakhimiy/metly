#!/bin/zsh
# Renders every App Store screenshot to PNG (1320 × 2868) with headless Chrome.
#   marketing/screenshots/export.sh            all languages that have raw captures
#   marketing/screenshots/export.sh uz en      only these
# Output: marketing/screenshots/out/<lang>/<n>.png
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
langs=("$@"); (( $# )) || langs=($(ls "$HERE/raw"))
for lang in $langs; do
  mkdir -p "$HERE/out/$lang"
  for n in 1 2 3 4 5; do
    out="$HERE/out/$lang/$n.png"
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
      --allow-file-access-from-files --window-size=1320,2868 --virtual-time-budget=2000 \
      --screenshot="$out" "file://$HERE/screenshot.html?lang=$lang&slide=$n" >/dev/null 2>&1
    echo "$out"
  done
done
