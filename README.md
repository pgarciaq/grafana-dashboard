# OpenShift Daily Costs by Project — Grafana Dashboard

Time series dashboard showing **daily cost per OpenShift project** for the last 30 days,
sourced from the Red Hat Cost Management API.

## Files

| File | Purpose |
|------|---------|
| `dashboard.json` | Grafana dashboard definition (import into Grafana) |
| `cost_proxy.py` | Flask proxy: authenticates to Red Hat SSO and flattens the API response |
| `import_dashboard.sh` | One-shot script to configure the datasource and import the dashboard |
| `README.md` | This file |

## Architecture

```
Grafana panel
    │  queries every 1 h
    ▼
cost_proxy.py  (localhost:5050)
    │  OAuth2 client credentials → Red Hat SSO token
    │  calls Cost Management API (last 30 days, daily, group_by project)
    │  flattens nested JSON → [{date, project, cost}, ...]
    ▼
console.redhat.com/api/cost-management/v1
```

The Grafana panel uses the **Infinity datasource** (backend parser) to read the flat
JSON array, then applies the **Partition by values** transformation to produce one time
series line per project.

> **Why a proxy?** The Infinity plugin v3.2 UQL parser does not process the nested
> `data[].projects[]` structure returned by the Cost Management API. The proxy flattens
> it into a simple array that the backend parser handles natively.

---

## Prerequisites

- Grafana with the **Infinity datasource plugin** (`yesoreyeram-infinity-datasource`)
- Python 3.8+ with `flask` and `requests`:
  ```bash
  pip3 install --user flask requests
  ```
- A Red Hat service account with access to Cost Management

---

## Quick start

```bash
# 1. Start the proxy
nohup python3 cost_proxy.py > /tmp/cost_proxy.log 2>&1 &

# 2. Configure the Grafana datasource and import the dashboard
bash import_dashboard.sh
```

Then open http://localhost:3000/d/ocp-costs-by-project

---

## Step 1 — Run the proxy

```bash
# Foreground (Ctrl-C to stop)
python3 cost_proxy.py

# Background, persistent across terminal sessions
nohup python3 cost_proxy.py > /tmp/cost_proxy.log 2>&1 &

# Verify
curl http://localhost:5050/health        # {"status": "ok"}
curl http://localhost:5050/ocp-costs-flat | python3 -m json.tool | head -20
```

The proxy exposes:

| Endpoint | Response |
|----------|----------|
| `GET /health` | `{"status": "ok"}` |
| `GET /ocp-costs-flat` | `[{"date": "2026-04-02", "project": "...", "cost": 123.4}, ...]` |

### Credentials

Hardcoded at the top of `cost_proxy.py`:

```
CLIENT_ID     = YOUR_CLIENT_ID
CLIENT_SECRET = YOUR_CLIENT_SECRET
```

Edit those constants to use a different service account.

---

## Step 2 — Configure the Infinity datasource

The datasource needs two things:

**Authentication (OAuth2 Client Credentials)**

| Field | Value |
|-------|-------|
| Token URL | `https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token` |
| Client ID | `YOUR_CLIENT_ID` |
| Client Secret | `YOUR_CLIENT_SECRET` |
| Scopes | `api.console` |

**Security → Allowed Hosts**

```
console.redhat.com
https://console.redhat.com
sso.redhat.com
localhost:5050
http://localhost:5050
```

`import_dashboard.sh` applies all of this automatically via the Grafana API.

---

## Step 3 — Import the dashboard

### Via the helper script (recommended)

```bash
bash import_dashboard.sh
```

### Manually via the Grafana UI

1. Open Grafana → **Dashboards → Import**
2. Upload `dashboard.json`
3. Select the **Cost Management API** Infinity datasource
4. Click **Import**

---

## Keeping the proxy alive after reboots

Create `/etc/systemd/system/cost-proxy.service`:

```ini
[Unit]
Description=Cost Management API proxy for Grafana
After=network.target

[Service]
ExecStart=/usr/bin/python3 /home/pgarciaq/dev/koku/grafana-dashboard/cost_proxy.py
Restart=always
User=pgarciaq

[Install]
WantedBy=multi-user.target
```

Enable it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now cost-proxy
sudo systemctl status cost-proxy
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Chart blank, legend shows data | Only 1 data point per series (start of month bug) | Fixed: proxy uses rolling 30-day scope |
| "URL not allowed" in Grafana | `localhost:5050` missing from Infinity allowed hosts | Re-run `import_dashboard.sh` |
| Proxy returns 401 | Expired or wrong service account credentials | Update `CLIENT_ID`/`CLIENT_SECRET` in `cost_proxy.py` |
| Proxy not reachable | Process died | Restart: `nohup python3 cost_proxy.py > /tmp/cost_proxy.log 2>&1 &` |
