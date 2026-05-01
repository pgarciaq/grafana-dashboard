# OpenShift Daily Costs by Project — Grafana Dashboard

Time series dashboard showing **daily cost per OpenShift project**, sourced from the
[Red Hat Cost Management API](https://console.redhat.com/api/cost-management/v1).
The date range is driven by the Grafana time picker — select "Last 7 days",
"Last 90 days", a custom range, etc. and the chart updates automatically.

## Repository structure

```
├── README.md                              ← this file
├── dashboard_native/                      ← recommended: no external dependencies
│   ├── README.md
│   ├── dashboard.json                     ← Grafana dashboard (queries API directly)
│   └── import_dashboard.sh               ← configures datasource + imports dashboard
└── dashboard_with_proxy/                  ← alternative: Flask proxy handles auth
    ├── README.md
    ├── cost_proxy.py                      ← Flask server (OAuth2 + JSON flattening)
    ├── dashboard.json                     ← Grafana dashboard (queries proxy)
    └── import_dashboard.sh               ← checks proxy, configures datasource + imports
```

---

## Prerequisites (both variants)

- **Grafana** with the [Infinity datasource plugin](https://grafana.com/grafana/plugins/yesoreyeram-infinity-datasource/) v3.x installed
- A **Red Hat service account** with access to Cost Management

### Service account credentials used in this repo

| Field | Value |
|---|---|
| Client ID | `YOUR_CLIENT_ID` |
| Client Secret | `YOUR_CLIENT_SECRET` |
| Token URL | `https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token` |
| Scopes | `api.console` |

To use a different service account, update the credentials in either the import
script (native variant) or `cost_proxy.py` (proxy variant).

---

## Variant 1: `dashboard_native/` — JSONata (recommended)

Grafana queries the Cost Management API **directly**. The Infinity datasource
authenticates via OAuth2 and uses a JSONata expression to flatten the nested
`data[].projects[].values[]` response into `{date, project, cost}` rows.

```bash
cd dashboard_native
bash import_dashboard.sh
```

**Requires:** Grafana + Infinity plugin v3.x. Nothing else.

See [`dashboard_native/README.md`](dashboard_native/README.md) for details.

---

## Variant 2: `dashboard_with_proxy/` — Flask proxy

A small Python server (`cost_proxy.py`) runs on `localhost:5050`, handles OAuth2
authentication, calls the Cost Management API, and returns a flat
`[{date, project, cost}]` JSON array. Grafana reads the flat JSON with no
special parsing or auth config needed.

```bash
cd dashboard_with_proxy
pip3 install --user flask requests
nohup python3 cost_proxy.py > /tmp/cost_proxy.log 2>&1 &
bash import_dashboard.sh
```

**Requires:** Grafana + Infinity plugin, Python 3.8+ with `flask` and `requests`.

See [`dashboard_with_proxy/README.md`](dashboard_with_proxy/README.md) for details.

---

## When to use which

| | Native (JSONata) | With Proxy |
|---|---|---|
| External dependencies | None | Python + Flask |
| OAuth2 credentials stored in | Grafana datasource | `cost_proxy.py` |
| Works if Grafana can't reach the API | No | Yes (proxy on a host that can) |
| Extra processing (caching, filtering) | No | Easily extensible |
| Proxy process must be kept running | No | Yes |
| Recommended for most users | **Yes** | For special cases |

---

## How it works

### Data source

The [Cost Management API](https://console.redhat.com/api/cost-management/v1/reports/openshift/costs/)
returns daily cost data grouped by OpenShift project. The response is deeply nested:

```
data[] → projects[] → values[] → cost.total.value
```

The native variant flattens this with a JSONata expression:

```jsonata
$.data.projects.values.{"date": date, "project": project, "cost": cost.total.value}
```

The proxy variant does the same flattening in Python and serves a flat array.

### Time range

Both variants pass the Grafana time picker dates to the API using the
`start_date` and `end_date` query parameters (via Grafana's built-in
`${__from:date:YYYY-MM-DD}` and `${__to:date:YYYY-MM-DD}` variables).

### Grafana transformations

The dashboard applies two transformations to the flat table:

1. **Organize fields** — ensures `date` is the first column (time axis)
2. **Partition by values** on `project` — splits the table into one time
   series frame per project, producing one colored line per project

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| "URL not allowed" in Grafana | Missing allowed hosts in Infinity datasource | Re-run the `import_dashboard.sh` for your variant |
| Chart blank with very narrow time range | Only 1 data point per series (can't draw a line) | Widen the Grafana time picker to at least 2 days |
| 401 from API | Service account credentials expired or wrong | Update credentials in the import script or `cost_proxy.py` |
| All cost values are $0 | No cost model assigned in Cost Management | Assign a cost model with rates to the OCP source |
| Proxy variant: "proxy is not running" | `cost_proxy.py` process died | Restart: `nohup python3 cost_proxy.py > /tmp/cost_proxy.log 2>&1 &` |
| Legend shows "A" instead of project names | `displayName` not set correctly | Re-import the dashboard from the provided `dashboard.json` |
