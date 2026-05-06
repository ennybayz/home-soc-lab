# Scenario 2: SQL injection probing against DVWA

A web application with a vulnerable parameter is the bread and butter of opportunistic exploitation. This walkthrough shows the lab observing classic SQLi payloads hit DVWA and producing a tiered alert.

## Threat model

| Element | Detail |
|---|---|
| Technique | T1190 - Exploit Public-Facing Application |
| Asset | `dvwa` (a stand-in for any vulnerable internal or external web app) |
| Detection origin | Wazuh agent reads Apache access logs from inside DVWA's container |
| Custom rules | `100200` (SQLi signature), `100201` (active SQLi probing) |

## Pre-flight: get logs flowing

DVWA's official image runs Apache without an external Wazuh agent. There are two clean ways to feed its logs to the manager:

**Option A (recommended for the lab):** mount DVWA's `/var/log/apache2/` into the `ubuntu.target` container and have its agent watch that directory. Add this to the agent's `ossec.conf` (the snippet in `config/agent/ossec.conf.snippet.xml` already does this) and restart the agent.

**Option B:** install the Wazuh agent inside the DVWA container by extending its Dockerfile. More realistic but more work.

For the demo we use Option A. After the lab is up:

```bash
# Bind-mount apache logs from dvwa into ubuntu.target (one-off setup)
docker exec ubuntu.target mkdir -p /shared/dvwa-logs
docker cp dvwa:/var/log/apache2/. ubuntu.target:/shared/dvwa-logs/
# In a real deployment you would do this with a docker volume in compose.
```

Then point the agent at the directory. The simplest approach is to copy the `localfile` block from `config/agent/ossec.conf.snippet.xml` into `/var/ossec/etc/ossec.conf` inside the agent and restart it.

## How to run the attack

Initialise DVWA first: visit <http://localhost:8080>, log in (`admin` / `password`), and click "Create / Reset Database". Set DVWA Security to "low".

Then capture an authenticated cookie:

```bash
# In the browser DevTools -> Application -> Cookies, copy PHPSESSID and security
export DVWA_COOKIE='PHPSESSID=xxx; security=low'
./scripts/attacks/02-dvwa-sqli.sh
```

The script fires twelve different SQLi payloads at the vulnerable `?id=` parameter. Some are union-based, some boolean-based, one is time-based, and a couple use URL-encoded variants to mimic evasion.

## What you should see in the dashboard

Filter on `agent.name:ubuntu.target` and `rule.groups:web`.

| Order | Rule ID | Level | What it means |
|---|---|---|---|
| 1-12 | 31100 / 31108 | 6-7 | Built-in: web attack pattern observed in Apache access log |
| 1-12 | 100200 | 10 | home-soc-lab: SQL injection signature observed against DVWA |
| 1 | 100201 | 12 | home-soc-lab: Active SQL injection probing (10+ attempts in 120s) |

The 100201 alert is the high-signal one. A single SQLi pattern in a log can be a security scanner, a typo in a search field, or a bot probing without intent. Ten in two minutes from one source is hands-on activity.

## Why the rules are written this way

Wazuh ships with web-attack rules in the 31xxx range that already catch the obvious patterns (`UNION SELECT`, `OR 1=1`, etc.). Rule 100200 piggybacks on rule 31100 (generic web attack) and adds a regex check on the URL for SQLi keywords. This gives a more specific tag and a more useful description than the generic rule.

Rule 100201 then aggregates 100200 hits the same way 100100 did for SSH: ten of them in 120 seconds from the same source. The thresholds are looser than SSH because web scanners are noisier and you do not want to escalate on every passing automated probe.

The choice of regex `UNION|union|SELECT|select|sleep\(|SLEEP\(|--|%27|%22` covers:

- Classic union-based extraction
- Time-based blind SQLi (`SLEEP()`)
- SQL comment terminators (`--`)
- URL-encoded single and double quotes (`%27`, `%22`)

It deliberately does not try to catch every variant. Detection engineering is about building rules that catch real attacks reliably, not about achieving regex completeness.

## What this would change in a real estate

In a school environment you would chain this with two upstream controls:

1. **A WAF in front of the application.** Most schools sit behind Cloudflare or similar. The WAF blocks the worst-of-the-worst payloads and the SIEM rule becomes a defence-in-depth net rather than the primary control.
2. **Application logging.** Apache access logs only see the URL and response code. Application-level logs see the parsed parameters, the query that ran, and the user context. Routing those into Wazuh would let you write rules of the form "any query containing `UNION SELECT` reaching the database layer is a confirmed exploitation".

## Lessons learned

The interesting failure mode here is encoding. The first version of rule 100200 only matched plain-text SQLi keywords. The attack script's `%27 OR 1=1--` payload sailed straight through. Adding `%27|%22` to the regex caught it, but the broader lesson is that any rule operating on a URL must also consider the encoded form.

This is the kind of thing you only learn by running attacks against your own detections. A rule that looks correct in a code review can still be quietly broken in practice.
