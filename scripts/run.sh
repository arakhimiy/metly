#!/bin/zsh
# Build, install and launch the app in the iOS Simulator.
#
#   scripts/run.sh                       backend from Info.plist (METLY_API_BASE_URL build setting)
#   scripts/run.sh --local               the backend running on this Mac (http://localhost:3000)
#   scripts/run.sh --api https://…       any backend
#   scripts/run.sh --mock                the in-app mock server, no backend at all
#   scripts/run.sh --demo                start signed in with demo data (Debug builds)
#
# Unlike scripts/build.sh this signs the app for the simulator ("Sign to Run Locally"):
# an unsigned build has no app-group entitlement, so SwiftData cannot create its store and
# the app sits on a blank screen. Simulator: $METLY_SIM (default "iPhone 17 Pro").
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
KEY=$(print -n "$ROOT" | shasum | cut -c1-10)
DERIVED="$HOME/Library/Developer/Xcode/DerivedData/metly-$KEY"
PACKAGES="$HOME/Library/Developer/Xcode/DerivedData/metly-spm-cache"
SIM_NAME=${METLY_SIM:-iPhone 17 Pro}
LOCK="/tmp/metly-xcodebuild.lock"

launch_args=()
while (( $# )); do
  case "$1" in
    --local) launch_args+=(-MetlyAPIBaseURL http://localhost:3000) ;;
    --api)   shift; launch_args+=(-MetlyAPIBaseURL "${1:?--api needs a URL}") ;;
    --mock)  launch_args+=(-MetlyUseMockServer) ;;
    --demo)  launch_args+=(-MetlyDemoData) ;;
    -h|--help) sed -n 2,13p "$0"; exit 0 ;;
    *) echo "unknown option: $1 (see --help)"; exit 2 ;;
  esac
  shift
done

# Boot the simulator if needed and show it.
UDID=$(xcrun simctl list devices available -j | python3 -I -c '
import json, sys
name = sys.argv[1]
for runtime, devices in sorted(json.load(sys.stdin)["devices"].items(), reverse=True):
    for d in devices:
        if d["name"] == name and d["isAvailable"]:
            print(d["udid"]); sys.exit()
sys.exit(f"no available simulator named {name!r} (set METLY_SIM)")' "$SIM_NAME")
xcrun simctl boot "$UDID" 2>/dev/null || true
SIM_APP="$(xcode-select -p)/Applications/Simulator.app"
[[ -d "$SIM_APP" ]] && open "$SIM_APP" --args -CurrentDeviceUDID "$UDID" || true   # show it if possible

# Share the global build lock with scripts/build.sh (one xcodebuild at a time).
until mkdir "$LOCK" 2>/dev/null; do
  if [[ -f "$LOCK/pid" ]] && ! kill -0 "$(cat "$LOCK/pid")" 2>/dev/null; then rm -rf "$LOCK"; continue; fi
  echo "⏳ waiting for another build…"; sleep 3
done
echo $$ > "$LOCK/pid"; echo "$ROOT run" > "$LOCK/owner"
trap 'rm -rf "$LOCK"' EXIT INT TERM

echo "🔨 Building for $SIM_NAME…"
LOG="$DERIVED/last-run-build.log"; mkdir -p "$DERIVED"
if ! xcodebuild -project "$ROOT/Metly.xcodeproj" -scheme Metly \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DERIVED" -clonedSourcePackagesDirPath "$PACKAGES" \
    -quiet -skipPackagePluginValidation \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
    build > "$LOG" 2>&1; then
  grep -E "error:" "$LOG" | sort -u | head -40
  echo "❌ build failed — full log: $LOG"; exit 1
fi
rm -rf "$LOCK"; trap - EXIT INT TERM

APP="$DERIVED/Build/Products/Debug-iphonesimulator/Metly.app"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" "$BUNDLE_ID" "${launch_args[@]}" > /dev/null
echo "✅ $BUNDLE_ID running on $SIM_NAME ${launch_args[*]:-}"
