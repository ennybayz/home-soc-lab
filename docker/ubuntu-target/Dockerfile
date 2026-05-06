# Ubuntu target - simulates a corporate Linux host monitored by Wazuh.
# Has SSH exposed for brute-force scenarios and a Wazuh agent baked in.
FROM ubuntu:22.04

ARG WAZUH_VERSION=4.7.5
ARG WAZUH_MANAGER=wazuh.manager

ENV DEBIAN_FRONTEND=noninteractive

# Install base packages, Wazuh agent, lab user, and configure SSH + agent log monitoring
# in a single layer to keep the image small.
# LogLevel INFO is explicit so sshd logs "Failed password" via syslog -> auth.log -> Wazuh.
# auth.log is added to the agent's localfile list so the manager receives SSH auth events.
RUN apt-get update && apt-get install -y --no-install-recommends \
        openssh-server \
        rsyslog \
        sudo \
        curl \
        gnupg2 \
        lsb-release \
        ca-certificates \
        iputils-ping \
        net-tools \
        vim \
    && curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH \
        | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import \
    && chmod 644 /usr/share/keyrings/wazuh.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
        > /etc/apt/sources.list.d/wazuh.list \
    && apt-get update \
    && WAZUH_MANAGER="${WAZUH_MANAGER}" apt-get install -y wazuh-agent=${WAZUH_VERSION}-1 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -s /bin/bash labuser \
    && echo "labuser:Password1" | chpasswd \
    && usermod -aG sudo labuser \
    && mkdir -p /var/run/sshd \
    && sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config \
    && sed -i 's/^#\?LogLevel.*/LogLevel INFO/' /etc/ssh/sshd_config \
    && sed -i 's|</ossec_config>|<localfile><log_format>syslog</log_format><location>/var/log/auth.log</location></localfile>\n</ossec_config>|' \
        /var/ossec/etc/ossec.conf

# Custom entrypoint starts the Wazuh agent and sshd in the foreground
COPY --chmod=755 entrypoint.sh /entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
