#!/bin/zsh
# Asks for the Google iOS OAuth client ID and wires it into the app and the backend.
#
#   scripts/setup-google-signin.sh
#
# Writes GOOGLE_CLIENT_ID into the Metly app target (Debug and Release) and GOOGLE_CLIENT_IDS into
# backend/.env. The client ID is not a secret (it ships inside the app).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PBXPROJ="$ROOT/Metly.xcodeproj/project.pbxproj"
ENV_FILE="$ROOT/backend/.env"
BUNDLE_ID=$(grep -m1 -E 'PRODUCT_BUNDLE_IDENTIFIER = app\.[a-z0-9.]+\.ios;' "$PBXPROJ" | sed -E 's/.*= (.*);/\1/')
[[ -f "$ENV_FILE" ]] || { echo "No $ENV_FILE — run: cp backend/.env.example backend/.env"; exit 1; }

echo "Sign in with Google — setup"
echo "Google Cloud Console → Credentials → OAuth client ID of type iOS, bundle ID $BUNDLE_ID."
echo
while true; do
  read "CLIENT_ID?Client ID (….apps.googleusercontent.com): "
  CLIENT_ID=${CLIENT_ID//[[:space:]]/}
  [[ "$CLIENT_ID" =~ '^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$' ]] && break
  echo "  Expected something like 123456789-abc123def.apps.googleusercontent.com. Try again."
done

GOOGLE_CLIENT_ID="$CLIENT_ID" BUNDLE_ID="$BUNDLE_ID" python3 -I - "$PBXPROJ" "$ENV_FILE" <<'PY'
import os, re, sys
pbx, env = sys.argv[1], sys.argv[2]
cid, bundle = os.environ["GOOGLE_CLIENT_ID"], os.environ["BUNDLE_ID"]

# App target only: every buildSettings block whose bundle id is exactly the app's (not the widgets').
text = open(pbx).read()
def fix(block):
    if f"PRODUCT_BUNDLE_IDENTIFIER = {bundle};" not in block.group(0):
        return block.group(0)
    body = re.sub(r"\n\t+GOOGLE_CLIENT_ID = [^;]*;", "", block.group(0))
    return re.sub(r"(\n(\t+)INFOPLIST_FILE = )", rf'\n\2GOOGLE_CLIENT_ID = "{cid}";\1', body, count=1)
new, n = re.subn(r"buildSettings = \{.*?\n\t\t\t\};", fix, text, flags=re.S)
count = new.count(f'GOOGLE_CLIENT_ID = "{cid}";')
if count != 2:
    sys.exit(f"expected the app's Debug and Release settings, updated {count}; project left unchanged")
open(pbx, "w").write(new)

lines = open(env).read().splitlines()
for i, line in enumerate(lines):
    if line.startswith("GOOGLE_CLIENT_IDS="):
        lines[i] = f"GOOGLE_CLIENT_IDS={cid}"
        break
else:
    lines.append(f"GOOGLE_CLIENT_IDS={cid}")
open(env, "w").write("\n".join(lines) + "\n")
PY

echo
echo "✅ App (Debug + Release) GOOGLE_CLIENT_ID and backend GOOGLE_CLIENT_IDS = $CLIENT_ID"
echo "Tell Claude \"tayyor\" — it restarts the backend, rebuilds the app and tests Google sign-in."
