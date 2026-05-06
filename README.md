# home-soc-lab

A self-contained Security Operations Centre running on a single laptop. Wazuh SIEM monitors a small estate of intentionally vulnerable hosts, and three documented attack scenarios prove that the detections fire end-to-end.

The lab is built to be brought up in two commands, torn down in one, and rebuilt from a clean checkout in under fifteen minutes. Every component is pinned, documented, and version-controlled.

The Wazuh stack (manager, indexer, dashboard) sits on its own Docker subnet, and the monitored hosts (DVWA, an Ubuntu box with SSH) sit on a second subnet that the manager dual-homes into. Custom detection rules live in [`docker/wazuh/rules/local_rules.xml`](docker/wazuh/rules/local_rules.xml) and are mapped to MITRE ATT&CK techniques. Three documented attack scenarios under [`docs/detections/`](docs/detections/) exercise those rules end-to-end. See [`docs/architecture.md`](docs/architecture.md) for the network design, [`docs/setup.md`](docs/setup.md) for the install walkthrough, and [`scripts/setup/`](scripts/setup/) for bring-up, teardown, and host-agent enrolment.

## Architecture at a glance

```
                   Host laptop (16 GB RAM, Docker Desktop)
+---------------------------------------------------------------------+
|                                                                     |
|   home-soc-lab_soc  (172.26.0.0/24)                                 |
|   +------------------+  +------------------+  +------------------+  |
|   | wazuh.indexer    |  | wazuh.manager    |  | wazuh.dashboard  |  |
|   | 172.26.0.20      |<-| 172.26.0.10      |->| 172.26.0.30      |  |
|   | (OpenSearch)     |  | (rules + API)    |  | (web UI :443)    |  |
|   +------------------+  +---------+--------+  +------------------+  |
|                                   |                                 |
|                                   | agent traffic 1514/1515         |
|                                   v                                 |
|   home-soc-lab_lab  (172.27.0.0/24)                                 |
|   +------------------+      +-----------------------+               |
|   | dvwa             |      | ubuntu.target         |               |
|   | 172.27.0.20:80   |      | 172.27.0.30:22 (SSH)  |               |
|   | (vulnerable web) |      | (Wazuh agent built-in)|               |
|   +------------------+      +-----------------------+               |
|                                                                     |
+---------------------------------------------------------------------+
                                |
                                v
                    Attacker box (your shell)
                    runs scripts/attacks/*.sh
```

The two Docker networks mirror a real estate: the SOC tooling sits on a management plane, the monitored hosts sit on a data plane, and only the Wazuh manager is dual-homed. See [docs/architecture.md](docs/architecture.md) for the rationale and trade-offs.

## Quick-start

Prerequisites: Docker Desktop (or Docker Engine + Compose v2) and 16 GB RAM.

**Windows (PowerShell):**

```powershell
git clone https://github.com/<your-username>/home-soc-lab.git
cd home-soc-lab
Copy-Item docker\.env.example docker\.env    # then edit and rotate the demo passwords
.\scripts\setup\bootstrap.ps1               # generates certs, builds, brings stack up
```

**macOS / Linux (bash):**

```bash
git clone https://github.com/<your-username>/home-soc-lab.git
cd home-soc-lab
cp docker/.env.example docker/.env       # then edit and rotate the demo passwords
./scripts/setup/bootstrap.sh             # generates certs, builds, brings stack up
```

Wait roughly two minutes for the indexer to settle, then visit:

- Wazuh dashboard: <https://localhost> (admin / `INDEXER_PASSWORD` from `.env`)
- DVWA: <http://localhost:8080> (admin / password, then click "Create Database")
- Ubuntu target: `ssh -p 2222 labuser@localhost` (password `Password1`)

Tear down with `.\scripts\setup\teardown.ps1` on Windows (add `-Wipe` to remove volumes too) or `./scripts/setup/teardown.sh` on macOS/Linux.

## Detection scenarios

| # | Scenario | MITRE ATT&CK | Custom rules | Walkthrough |
|---|---|---|---|---|
| 1 | SSH brute-force followed by successful login | T1110.001, T1078 | 100100, 100101 | [docs/detections/01-ssh-bruteforce.md](docs/detections/01-ssh-bruteforce.md) |
| 2 | SQL injection probing against DVWA | T1190 | 100200, 100201 | [docs/detections/02-dvwa-sqli.md](docs/detections/02-dvwa-sqli.md) |
| 3 | Suspicious binary dropped to a temp path (FIM) | T1059, T1105 | 100300 | [docs/detections/03-fim-suspicious-binary.md](docs/detections/03-fim-suspicious-binary.md) |

Each walkthrough is structured the same way: the attack command, the alert chain it should produce in the Wazuh dashboard, and a short note on what the detection misses and how I would tune it.

## Repository layout

```
home-soc-lab/
|-- docker/
|   |-- docker-compose.yml              # The stack
|   |-- generate-certs.yml              # One-shot SSL cert generator
|   |-- .env.example                    # Secrets template
|   |-- ubuntu-target/                  # Custom image: Ubuntu + sshd + Wazuh agent
|   `-- wazuh/
|       |-- config/                     # Indexer + dashboard config
|       |-- rules/local_rules.xml       # Custom detection rules
|       `-- decoders/local_decoder.xml  # Placeholder for future log sources
|-- config/
|   `-- agent/ossec.conf.snippet.xml    # Drop-in agent config (FIM, Apache logs)
|-- scripts/
|   |-- setup/bootstrap.sh              # First-run bring-up
|   |-- setup/teardown.sh               # Stop + optional wipe
|   |-- setup/install-agent-on-host.sh  # Enrol a real Linux host
|   `-- attacks/                        # Reproducible attack simulations
|-- docs/
|   |-- architecture.md                 # Network diagram, design rationale
|   |-- setup.md                        # Detailed install + troubleshooting
|   `-- detections/                     # Per-scenario walkthroughs
|-- LICENSE
`-- README.md
```

## Roadmap

Things I would build next if this were going further:

1. Replace the single-node indexer with a three-node cluster to demonstrate high-availability design.
2. Terraform module that lifts the same architecture onto AWS or Azure (Wazuh manager on EC2 / Azure VM, agents on private-subnet hosts).
3. Wazuh active response playbooks (IP block on brute-force, file quarantine on FIM hit) wired to a small webhook server.
4. Replace DVWA with a more realistic target stack (a vulnerable Spring Boot app exercising CVE-2022-22965, tying back to a previous university project).

## Licence

MIT - see [LICENSE](LICENSE).
