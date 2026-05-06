#!/bin/bash
# entrypoint.sh - start Wazuh agent and OpenSSH together so the container
# survives as a single foreground process (sshd) while the agent runs in
# the background. Logs from both are reachable via `docker logs`.

set -euo pipefail

# rsyslog must start first so /dev/log exists before sshd launches.
# Without it, sshd has nowhere to write syslog messages and auth.log is never created.
rsyslogd || true

# Start the Wazuh agent. It enrols with the manager defined at build time
# (WAZUH_MANAGER ARG) and ships logs over port 1514.
service wazuh-agent start || true

# Tail both the Wazuh agent log and auth.log so they surface in `docker logs ubuntu.target`
tail -F /var/ossec/logs/ossec.log &
tail -F /var/log/auth.log &

# Run sshd in the foreground - this keeps the container alive
# No -e flag: sshd logs via syslog -> auth.log -> Wazuh agent (not stderr)
exec /usr/sbin/sshd -D
