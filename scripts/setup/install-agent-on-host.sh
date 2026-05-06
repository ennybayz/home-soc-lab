#!/usr/bin/env bash
# install-agent-on-host.sh
# Installs the Wazuh agent on a real Linux host (laptop, classroom server, etc.)
# rather than the lab's containerised target. Useful when demoing how the SIEM
# would monitor a school's actual workstations.
#
# Requires: a Debian/Ubuntu host with sudo, and the manager reachable on 1514/1515.
#
# Usage:
#   sudo MANAGER=192.168.1.50 ./install-agent-on-host.sh

set -euo pipefail

MANAGER="${MANAGER:?Set MANAGER to the IP/hostname of your Wazuh manager}"
WAZUH_VERSION="${WAZUH_VERSION:-4.7.5}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run with sudo"
  exit 1
fi

echo "==> Adding Wazuh apt repository"
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring \
  --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import
chmod 644 /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
  > /etc/apt/sources.list.d/wazuh.list

apt-get update
WAZUH_MANAGER="$MANAGER" apt-get install -y "wazuh-agent=${WAZUH_VERSION}-1"

echo "==> Enabling and starting the agent"
systemctl daemon-reload
systemctl enable wazuh-agent
systemctl start wazuh-agent

echo
echo "Done. Verify enrolment on the manager:"
echo "  docker exec -it wazuh.manager /var/ossec/bin/agent_control -l"
