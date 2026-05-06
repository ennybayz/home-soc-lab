# Setup guide

End-to-end install on a fresh machine. Allow about thirty minutes for the first run, mostly waiting on image pulls.

## Prerequisites

| Requirement | Why |
|---|---|
| Docker Desktop 4.x or Docker Engine 24+ with Compose v2 | Stack is multi-container with healthchecks and named volumes |
| 16 GB RAM (8 GB allocated to Docker if on Desktop) | Indexer alone reserves a 2 GB Java heap |
| 20 GB free disk | Image layers + indexer data + logs |
| `bash` | Setup and attack scripts assume a POSIX shell |
| `git` | Cloning the repo |

On Linux you also need `vm.max_map_count >= 262144`. The bootstrap script raises it for you.

## Step 1: Clone and configure

```bash
git clone https://github.com/<your-username>/home-soc-lab.git
cd home-soc-lab
cp docker/.env.example docker/.env
```

Open `docker/.env` and rotate the three demo passwords. The values become the credentials for:

- `INDEXER_PASSWORD` -> Wazuh indexer admin user (and dashboard login)
- `API_PASSWORD` -> the `wazuh-wui` API user the dashboard uses
- `DASHBOARD_PASSWORD` -> the `kibanaserver` service account

If you are demoing this and want to keep things simple, leave the values as shipped, but never commit a `.env` with real passwords.

## Step 2: Run the bootstrap

```bash
./scripts/setup/bootstrap.sh
```

The script does five things:

1. Verifies `docker` and `docker compose` are present.
2. Raises `vm.max_map_count` on Linux hosts (skipped on macOS/Windows).
3. Copies `.env.example` to `.env` if you have not done it yourself.
4. Runs the cert generator container, which writes a CA, manager, indexer, and dashboard certificates into `docker/wazuh/config/wazuh_indexer_ssl_certs/`.
5. Pulls images, builds the `ubuntu.target` image, and brings the stack up in detached mode.

You should see something like:

```
[+] Running 5/5
 - Container wazuh.indexer    Started
 - Container dvwa             Started
 - Container ubuntu.target    Started
 - Container wazuh.manager    Started
 - Container wazuh.dashboard  Started
```

## Step 3: Wait for the indexer

The indexer needs a couple of minutes to initialise its security plugin and accept connections. Tail its logs while you wait:

```bash
docker logs -f wazuh.indexer
```

You are looking for `Node 'wazuh.indexer' initialized` and `Cluster state is now GREEN`. If it stays YELLOW, that is fine for a single-node setup.

## Step 4: First login

Open <https://localhost> in a browser. You will get a TLS warning because the CA is self-signed; accept it for now (or import `docker/wazuh/config/wazuh_indexer_ssl_certs/root-ca.pem` into your trust store to silence it).

Log in with `admin` and your `INDEXER_PASSWORD`. The dashboard should redirect you to the Wazuh app home page (`/app/wazuh`).

If you see "Wazuh API not reachable", give the manager another thirty seconds and refresh.

## Step 5: Confirm the agent enrolled

Check the manager:

```bash
docker exec -it wazuh.manager /var/ossec/bin/agent_control -l
```

Expected output (one line per agent):

```
   ID: 000, Name: wazuh.manager (server), IP: 127.0.0.1
   ID: 001, Name: ubuntu.target, IP: any, Active
```

If `ubuntu.target` does not appear, it usually means the agent could not resolve `wazuh.manager`. Restart it: `docker restart ubuntu.target`.

## Step 6: Initialise DVWA

DVWA needs a one-time database setup. Open <http://localhost:8080>, log in with `admin` / `password`, and click **Create / Reset Database** at the bottom of the setup page. After that, set the security level to "low" under DVWA Security so the SQLi scenario succeeds.

## Step 7: Run a detection scenario

Pick one of the walkthroughs in [`docs/detections/`](detections/) and follow it. The shortest path to a visible alert is the brute-force scenario, which needs no DVWA setup and only the standard `sshpass` tool.

```bash
sudo apt install sshpass        # or brew install hudochenkov/sshpass/sshpass
./scripts/attacks/01-ssh-bruteforce.sh
```

Then in the dashboard go to **Modules -> Security events** and filter for `rule.id:100100`. You should see at least one alert within ten seconds.

## Troubleshooting

### Indexer keeps restarting

Almost always `vm.max_map_count`. On Linux:

```bash
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
```

On Docker Desktop, the setting lives inside the Linux VM Docker Desktop manages. Recent versions handle it automatically; if not, you may need to recreate the VM.

### Manager logs say "filebeat: connection refused"

The indexer has not finished starting. Wait another minute, then `docker restart wazuh.manager`.

### Dashboard shows "Wazuh API not reachable"

Check that the API password in `.env` matches the password baked into the dashboard's `wazuh.yml`. By default both are `wazuh-wui`. If you change one, change the other.

### Brute-force scenario does not generate alerts

Two common causes:

1. The agent is not enrolled - re-check Step 5.
2. The auth.log decoder is finding a different format. `docker exec ubuntu.target cat /var/log/auth.log` and confirm the failed-password lines look like `sshd[...]: Failed password for invalid user ... from ...`.

### Tearing down for a clean slate

```bash
./scripts/setup/teardown.sh --wipe
```

That removes containers, volumes, and the generated certificate bundle. The next bootstrap run will regenerate everything.
