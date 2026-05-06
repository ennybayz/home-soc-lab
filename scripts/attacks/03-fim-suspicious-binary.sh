#!/usr/bin/env bash
# 03-fim-suspicious-binary.sh
# Drops a suspicious-looking shell script into /tmp on the Ubuntu target
# to exercise File Integrity Monitoring (syscheck) and rule 100300.
#
# Runs the drop *inside* the container so syscheck on the agent observes it.

set -euo pipefail

TARGET_CONTAINER="${TARGET_CONTAINER:-ubuntu.target}"

command -v docker >/dev/null || { echo "docker required"; exit 1; }

echo "==> Dropping a fake malicious script in /tmp inside ${TARGET_CONTAINER}"
docker exec "$TARGET_CONTAINER" bash -c '
  cat > /tmp/totally-not-malware.sh <<EOF
#!/bin/bash
# Lab demo file. Real malware would never be this honest.
echo "pretending to do something nasty"
EOF
  chmod +x /tmp/totally-not-malware.sh
  ls -la /tmp/totally-not-malware.sh
'

echo
echo "==> Modifying it a few seconds later to also trigger a 'modified' event"
sleep 3
docker exec "$TARGET_CONTAINER" bash -c '
  echo "extra line $(date)" >> /tmp/totally-not-malware.sh
'

echo
echo "Check the Wazuh dashboard -> Modules -> Integrity monitoring."
echo "Expected alerts:"
echo "  - rule 554            (file added in monitored path)"
echo "  - rule 550            (file modified)"
echo "  - rule 100300         (home-soc-lab suspicious executable in /tmp)"
