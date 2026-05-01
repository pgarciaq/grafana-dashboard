# Dashboard: With Proxy (Flask)

Grafana queries a local **Flask proxy** that authenticates to Red Hat SSO and
flattens the Cost Management API response into a simple `[{date, project, cost}]`
array. The Infinity datasource reads the flat JSON — no OAuth2 or JSONata config
needed on the Grafana side.

## Architecture

```
Grafana  ──(Infinity, plain HTTP)──►  cost_proxy.py (localhost:5050)
                                           │
                                           │  OAuth2 client credentials → Red Hat SSO
                                           │  GET /reports/openshift/costs/
                                           │  Flattens nested JSON
                                           ▼
                                      console.redhat.com/api/cost-management/v1
```

## Prerequisites

- Grafana with the **Infinity datasource plugin** (`yesoreyeram-infinity-datasource` v3.x)
- Python 3.8+ with `flask` and `requests`:
  ```bash
  pip3 install --user flask requests
  ```
- A Red Hat service account with access to Cost Management

## Quick start

```bash
# 1. Start the proxy
nohup python3 cost_proxy.py > /tmp/cost_proxy.log 2>&1 &

# 2. Configure datasource + import dashboard
bash import_dashboard.sh
```

Then open the URL printed by the script.

## What the import script does

1. Verifies the proxy is running at `http://localhost:5050`
2. Creates (or updates) an Infinity datasource named **Cost Management API (proxy)** with:
   - No authentication (the proxy handles OAuth2)
   - Allowed hosts: `localhost:5050`
3. Imports `dashboard.json`, wiring it to the datasource

## Time range

The proxy accepts `start_date` and `end_date` query parameters (YYYY-MM-DD).
The dashboard URL includes `${__from:date:YYYY-MM-DD}` and `${__to:date:YYYY-MM-DD}`,
so the data automatically matches whatever you select in the Grafana time picker.

If no dates are passed, the proxy defaults to the last 30 days.

## Proxy details

| Endpoint | Description |
|---|---|
| `GET /health` | Health check (`{"status": "ok"}`) |
| `GET /ocp-costs-flat` | Flat cost array (accepts `start_date`, `end_date` query params) |

### Credentials

Hardcoded at the top of `cost_proxy.py`:

```
CLIENT_ID     = YOUR_CLIENT_ID
CLIENT_SECRET = YOUR_CLIENT_SECRET
```

Edit those constants to use a different service account.

### Keeping the proxy alive

```bash
# systemd unit
sudo tee /etc/systemd/system/cost-proxy.service <<EOF
[Unit]
Description=Cost Management API proxy for Grafana
After=network.target

[Service]
ExecStart=/usr/bin/python3 $(pwd)/cost_proxy.py
Restart=always
User=$USER

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now cost-proxy
```

## When to use this variant

- Your Grafana version or Infinity plugin version doesn't support JSONata
- You want the proxy to do extra processing (caching, filtering, aggregation)
- You prefer keeping API credentials outside of Grafana
- Your Grafana instance can't reach `console.redhat.com` directly (proxy runs on a host that can)
