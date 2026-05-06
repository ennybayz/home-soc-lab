# Architecture

This document explains the lab's structure and the reasoning behind it. The goal was to build something small enough to run on a 16 GB laptop, but laid out in a way that scales mentally to a real estate.

## Network topology

The lab uses two Docker bridge networks. The Wazuh manager has an interface on each.

```
                +-------------------------- soc 172.20.0.0/24 --------------------------+
                |                                                                       |
                |   wazuh.indexer (.20)         wazuh.manager (.10)         wazuh.dashboard (.30)
                |   OpenSearch backend          rules + agent ingest         web UI on :443
                |                                                                       |
                +-------------------------+---------------+-----------------------------+
                                          |               |
                                          | host-published ports
                                          | 9200 / 443 / 1514 / 1515 / 55000
                                          v
                                  Operator browser / API client

                +-------------------------- lab 172.21.0.0/24 --------------------------+
                |                                                                       |
                |   dvwa (.20)                                ubuntu.target (.30)       |
                |   PHP web app, vulnerable by design          sshd + Wazuh agent       |
                |                                                                       |
                +-------------------------+---------------------------------------------+
                                          ^
                                          | host-published ports
                                          | 8080 -> dvwa:80
                                          | 2222 -> ubuntu.target:22
                                          v
                                  Attacker shell / scripts/attacks/*.sh
```

### Why two networks?

A real SIEM deployment has a clean separation between the management plane (where SOC analysts work) and the data plane (the monitored estate). Putting everything on a single flat network is convenient but trains the wrong instincts.

Splitting into `soc` and `lab` networks does three useful things:

1. **It mirrors a school's likely topology.** Staff laptops, classroom workstations, and BYOD devices live on user VLANs. Servers and management tooling live on a separate VLAN. The Wazuh manager bridges the two because it has to receive logs from the data plane while exposing its API to the management plane.
2. **It makes the failure modes explicit.** If `dvwa` is compromised, the attacker can pivot to `ubuntu.target` (same network) but cannot directly reach `wazuh.indexer`. They have to go through the manager, which is monitored.
3. **It is the smallest design that demonstrates segmentation.** Adding more networks (DMZ, server, user) is straightforward, but two is enough to show the principle.

### Trade-offs

| Choice | Why | What we give up |
|---|---|---|
| Single-node indexer (no cluster) | Fits in 16 GB, faster boot, simpler config | No HA - a single OOM kills ingest. Roadmap item #1 fixes this. |
| Bridge networks instead of `macvlan` | Works on Docker Desktop on macOS / Windows where `macvlan` is awkward | Containers cannot present unique L2 MACs to a real switch |
| TLS with self-signed CA | Simple, no external dependencies, demonstrates cert pipeline | Browser warnings on first visit, must install CA in browser for cleanliness |
| DVWA image (PHP) | Well-known, runs in <100 MB, lots of vulnerable surfaces | Old Ubuntu base, occasional patch issues. Roadmap item #4 swaps it. |

## Component breakdown

### Wazuh manager (`172.20.0.10`, dual-homed)

Receives agent traffic on TCP/1514 (events) and TCP/1515 (enrolment). Loads built-in and custom rules from `/var/ossec/etc/rules/`. Exposes a REST API on `:55000` that the dashboard talks to.

Custom rules are mounted in from `docker/wazuh/rules/local_rules.xml`. This means rule changes require a container restart but never an image rebuild, which suits an iterative tuning workflow.

### Wazuh indexer (`172.20.0.20`)

OpenSearch fork that stores events, alerts, and asset inventory. Exposes HTTPS on `:9200`. The indexer's heap is fixed at 2 GB through `OPENSEARCH_JAVA_OPTS` so it cannot consume more memory than the host can spare.

Internal users and certificates are mounted in - the lab does not initialise a fresh OpenSearch cluster every boot.

### Wazuh dashboard (`172.20.0.30`)

OpenSearch Dashboards fork. Talks to the indexer over TLS using the `kibanaserver` service account. Talks to the manager API using the `wazuh-wui` user.

The dashboard is the only component published on `:443` to the host. Everything else stays inside the Docker network.

### DVWA target (`172.21.0.20`)

The Damn Vulnerable Web Application. Lives on the lab network only. Apache logs inside the container would normally be the source for the SQLi detection scenario; in this build, the simpler approach is to run a Wazuh agent inside DVWA's container or to ship Apache access logs via syslog. The walkthrough in `docs/detections/02-dvwa-sqli.md` covers both options.

### Ubuntu target (`172.21.0.30`)

Custom image based on `ubuntu:22.04`. Ships with:

- OpenSSH server bound to `:22` (published as `:2222` on the host)
- Wazuh agent installed via the official apt repository at build time
- A `labuser` account with the deliberately weak password `Password1`

The agent enrols against `wazuh.manager` on first boot using the `WAZUH_MANAGER` build arg. SSH password authentication is enabled (Ubuntu disables it by default) so the brute-force scenario has a foothold.

## Data flow for a single SSH login event

```
labuser logs in over SSH
        |
        v
sshd writes /var/log/auth.log inside ubuntu.target
        |
        v
Wazuh agent's logcollector reads the new line
        |
        v
Agent ships the event over TLS to wazuh.manager:1514
        |
        v
Manager runs decoders (sshd decoder is built-in) -> field extraction
        |
        v
Manager evaluates rules in order. Rule 5710 fires for failed auth,
rule 5715 fires for success. Custom rule 100100 fires when 5710 hits
six times within 60 seconds from the same source IP.
        |
        v
Manager sends the alert to the indexer via Filebeat (TLS)
        |
        v
Indexer writes to wazuh-alerts-* index
        |
        v
Dashboard queries the index and renders the alert
```

This is the same flow you would see with hundreds of agents in a school estate. The only thing that changes at scale is the number of indexer nodes and whether you put a load balancer in front of the manager.

## What this design says about the operator (positioning angle)

An architecture diploma produces a habit of reading a brief, scoping it to the available footprint, and documenting decisions so the next person can pick up the work. The SOC lab is structured the same way:

- The brief: "demonstrate end-to-end SIEM operation on a single laptop, in a way a non-author can rebuild from scratch."
- The constraints: 16 GB of RAM, a tomorrow deadline, a single host network.
- The decisions: documented in this file, with explicit trade-offs.
- The handover artefacts: README, setup guide, three walkthroughs, teardown script.

Where a building project lives or dies on its drawings, a software project lives or dies on its README and architecture document. This lab treats those documents as the primary deliverables.
