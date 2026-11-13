#!/bin/zsh
# Serialised xcodebuild for parallel agents (8 GB machine: never run two builds at once).
#
#   scripts/build.sh <Scheme> [build|test]      e.g. scripts/build.sh FeaturePeople
#   scripts/build.sh app [build|test]           whole app (Metly.xcodeproj, scheme Metly)
#   scripts/build.sh all test                   every MetlyKit test target (what CI runs)
#
# Builds are UNSIGNED (fast, no team needed) and only prove the code compiles/tests pass.
# To run the app in the simulator use scripts/run.sh, which signs it for the simulator.
#
# Package schemes (module names) build from Packages/MetlyKit. Uses a per-checkout DerivedData
# so git worktrees never share build products, plus a global lock so only one build runs.
set -euo pipefail

SCHEME=${1:?usage: scripts/build.sh <Scheme|app|all> [build|test]}
ACTION=${2:-build}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KEY=$(print -n "$ROOT" | shasum | cut -c1-10)
DERIVED="$HOME/Library/Developer/Xcode/DerivedData/metly-$KEY"
PACKAGES="$HOME/Library/Developer/Xcode/DerivedData/metly-spm-cache"
LOCK="/tmp/metly-xcodebuild.lock"
SIM_NAME=${METLY_SIM:-iPhone 17 Pro}

# --- global lock (mkdir is atomic) ---
waited=0
until mkdir "$LOCK" 2>/dev/null; do
  if [[ -f "$LOCK/pid" ]] && ! kill -0 "$(cat "$LOCK/pid")" 2>/dev/null; then rm -rf "$LOCK"; continue; fi
  (( waited % 30 == 0 )) && echo "⏳ waiting for another build ($(cat "$LOCK/owner" 2>/dev/null))…"
  sleep 2; (( waited += 2 ))
done
echo $$ > "$LOCK/pid"; echo "$ROOT $SCHEME" > "$LOCK/owner"
trap 'rm -rf "$LOCK"' EXIT INT TERM

if [[ "$ACTION" == test ]]; then
  # By UDID: a name alone is ambiguous when other projects keep simulators of the same device type.
  SIM_ID=$(xcrun simctl list devices available -j | python3 -I -c '
import json, sys
name = sys.argv[1]
for runtime, devices in sorted(json.load(sys.stdin)["devices"].items(), reverse=True):
    for d in devices:
        if d["name"] == name and d["isAvailable"]:
            print(d["udid"]); sys.exit()
sys.exit(f"no available simulator named {name!r} (set METLY_SIM)")' "$SIM_NAME")
  DEST="platform=iOS Simulator,id=$SIM_ID"
else
  DEST="generic/platform=iOS Simulator"
fi

common=(-destination "$DEST" -derivedDataPath "$DERIVED" -clonedSourcePackagesDirPath "$PACKAGES"
        -jobs 4 -quiet -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO)

LOG="$DERIVED/last-build.log"; mkdir -p "$DERIVED"
set +e
if [[ "$SCHEME" == app ]]; then
  cd "$ROOT"
  xcodebuild -project Metly.xcodeproj -scheme Metly "${common[@]}" "$ACTION" > "$LOG" 2>&1
else
  cd "$ROOT/Packages/MetlyKit"
  if [[ "$SCHEME" == all ]]; then
    xcodebuild -scheme MetlyKit-Package "${common[@]}" "$ACTION" > "$LOG" 2>&1
  elif [[ "$ACTION" == test ]]; then
    xcodebuild -scheme MetlyKit-Package "${common[@]}" -only-testing:"${SCHEME}Tests" test > "$LOG" 2>&1
  else
    xcodebuild -scheme "$SCHEME" "${common[@]}" build > "$LOG" 2>&1
  fi
fi
rc=$?
set -e
grep -E "error:|✘|Test run with|passed after|failed after|\*\* (BUILD|TEST)" "$LOG" | sort -u | head -80 || true
[[ $rc -eq 0 ]] && echo "✅ $SCHEME $ACTION succeeded" || echo "❌ $SCHEME $ACTION failed ($rc) — full log: $LOG"
exit $rc
