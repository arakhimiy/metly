#!/bin/zsh
# Asks for the Log In with Telegram settings and writes them to backend/.env.
#
#   scripts/setup-telegram-login.sh
#
# Values come from @BotFather → mini app → your bot → Login Widget. The bot token is NOT used.
# The client secret is read without echo and never printed.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
ENV_FILE="$ROOT/backend/.env"
[[ -f "$ENV_FILE" ]] || { echo "No $ENV_FILE — run: cp backend/.env.example backend/.env"; exit 1; }

current() { grep -E "^$1=" "$ENV_FILE" | tail -1 | cut -d= -f2- || true; }

echo "Log In with Telegram — setup"
echo "Open @BotFather → mini app → your bot → Login Widget. (Do NOT paste the bot token.)"
echo

# 1. Client ID (numeric).
while true; do
  read "CLIENT_ID?1/3  Client ID (digits): "
  [[ "$CLIENT_ID" =~ '^[0-9]+$' ]] && break
  echo "     Client ID is a number, e.g. 123456789. Try again."
done

# 2. Client Secret (hidden).
while true; do
  read -s "CLIENT_SECRET?2/3  Client Secret (hidden): "; echo
  [[ -n "$CLIENT_SECRET" && "$CLIENT_SECRET" != *[[:space:]]* ]] && break
  echo "     Empty or contains spaces. Try again."
done

# 3. Public HTTPS address of the API (Telegram sends the browser back there).
API_NOW=$(current API_BASE_URL)
echo "3/3  Public HTTPS address of this API (where Telegram redirects back)."
echo "     e.g. https://api.tanishly.app or a tunnel URL. Enter = keep \"$API_NOW\"."
while true; do
  read "API_URL?     API base URL: "
  API_URL=${API_URL:-$API_NOW}
  API_URL=${API_URL%/}
  [[ "$API_URL" =~ '^https?://[^ ]+$' ]] && break
  echo "     Must start with https:// (or http:// for localhost). Try again."
done

TELEGRAM_LOGIN_CLIENT_ID="$CLIENT_ID" TELEGRAM_LOGIN_CLIENT_SECRET="$CLIENT_SECRET" API_BASE_URL="$API_URL" \
python3 -I - "$ENV_FILE" <<'PY'
import os, re, sys
path = sys.argv[1]
keys = ["TELEGRAM_LOGIN_CLIENT_ID", "TELEGRAM_LOGIN_CLIENT_SECRET", "API_BASE_URL"]
lines = open(path).read().splitlines()
for key in keys:
    line = f"{key}={os.environ[key]}"
    for i, old in enumerate(lines):
        if re.match(rf"^{key}=", old):
            lines[i] = line
            break
    else:
        lines.append(line)
open(path, "w").write("\n".join(lines) + "\n")
PY

echo
echo "✅ Saved to backend/.env: TELEGRAM_LOGIN_CLIENT_ID=$CLIENT_ID, TELEGRAM_LOGIN_CLIENT_SECRET=(hidden), API_BASE_URL=$API_URL"
echo
echo "Now in @BotFather → Login Widget → Allowed URLs, add exactly:"
echo "    $API_URL/v1/auth/telegram/callback"
if [[ "$API_URL" == http://* ]]; then
  echo "⚠️  $API_URL is not HTTPS — Telegram may refuse it. Use a public HTTPS URL (tunnel or the live API)."
fi
echo
echo "Then tell Claude \"tayyor\" — it restarts the backend and tests the sign-in."
