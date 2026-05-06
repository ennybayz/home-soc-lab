# Scenario 3: Suspicious binary dropped to a temp path

After initial access, attackers commonly stage tools in writable directories like `/tmp` or `/dev/shm`. File Integrity Monitoring (FIM) is the cheapest reliable way to catch that on a Linux host.

## Threat model

| Element | Detail |
|---|---|
| Technique | T1059 - Command and Scripting Interpreter |
| Technique | T1105 - Ingress Tool Transfer |
| Asset | `ubuntu.target` (any monitored Linux host) |
| Detection origin | Wazuh syscheck (FIM) module on the agent, real-time mode |
| Custom rules | `100300` (suspicious executable in a temp path) |

## Pre-flight: real-time FIM on /tmp

The lab's agent ships with the `<syscheck>` block from `config/agent/ossec.conf.snippet.xml`, which monitors `/tmp` and `/dev/shm` in real-time mode.

Verify it is active:

```bash
docker exec ubuntu.target tail -n 50 /var/ossec/logs/ossec.log | grep -i syscheck
```

You should see something like `Starting syscheck scan` and `Real-time file monitoring engine started`.

## How to run the attack

```bash
./scripts/attacks/03-fim-suspicious-binary.sh
```

The script:

1. Drops a small shell script at `/tmp/totally-not-malware.sh` inside the target.
2. Sets the executable bit.
3. Waits a few seconds, then appends a line to it (so a "modified" event also fires).

In a real intrusion this is what you would see when an attacker `wget`s a tool, `chmod +x`s it, and runs it.

## What you should see in the dashboard

Go to **Modules -> Integrity monitoring** in the Wazuh dashboard, then filter on `agent.name:ubuntu.target`.

| Order | Rule ID | Level | What it means |
|---|---|---|---|
| 1 | 554 | 5 | syscheck: file added to monitored directory |
| 1 | 100300 | 11 | home-soc-lab: Suspicious executable dropped in temp path |
| 2 | 550 | 7 | syscheck: file modified |

The level-11 alert is the one to action. Level 5 (file added) on its own is normal background activity, especially in `/tmp`.

## Why the rule is written this way

FIM events alone are noisy. `/tmp` churns constantly with build artefacts, package manager state, and editor swap files. Alerting on every change would bury the signal.

Rule 100300 narrows the scope by combining three signals:

1. The path matches `/tmp/.*` or `/dev/shm/.*`
2. The file extension matches `.sh`, `.elf`, `.bin`, or `.py`
3. The event is a syscheck event (rule IDs 550, 553, 554)

The extension filter is a coarse heuristic and is bypassable: an attacker who renames `payload.elf` to `kbd-driver` will not match. That is fine. The rule is one layer of defence-in-depth, not the only line. Roadmap item #3 (active response) would automatically quarantine the matched file, raising the cost of the simple bypass while the analyst investigates.

## What this would change in a real estate

In a school environment, FIM becomes most useful in two places:

1. **On classroom workstations.** Students legitimately drop files in their home directories all day, but `/usr/local/bin`, `/etc`, and the system service directories should be quiet. FIM with tight rules on system paths catches malware that needs persistence.
2. **On servers.** A school's file server or MIS host should have an extremely stable filesystem. Any change to `/etc` or `/usr` outside a maintenance window is worth investigating.

The same syscheck engine handles both. The only thing that changes is which directories you monitor and at what frequency.

## Lessons learned

The default `<syscheck>` config scans every six hours. That is fine for forensic reconstruction but useless for real-time detection: an attacker is in and out long before the next scheduled scan. Setting `realtime="yes"` on the directory entry makes the kernel's `inotify` API push events to the agent within milliseconds.

There is a memory cost: real-time monitoring has to keep an inotify watch on every file in the tree. On `/tmp` this is fine. On `/usr/lib` it is not. The right default is real-time on small high-value directories, scheduled scans on everything else.
