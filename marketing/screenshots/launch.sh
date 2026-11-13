#!/bin/zsh
# Relaunches the installed app with demo data in one language: launch.sh <uz|ru|en>
# The language goes in as launch arguments (UserDefaults argument domain), which override what
# the app saved, so nothing is written to the app's own settings.
set -euo pipefail
SIM=${METLY_SIM_UDID:-5EDB177C-B727-4874-9FA0-E6295FC00B83}
xcrun simctl terminate "$SIM" app.nameshake.ios 2>/dev/null || true
xcrun simctl launch "$SIM" app.nameshake.ios -MetlyUseMockServer -MetlyDemoData \
  -pref.language "$1" -AppleLanguages "($1)" >/dev/null
