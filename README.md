# OpenShift Daily Costs by Project — Grafana Dashboard

Time series dashboard showing **daily cost per OpenShift project**, sourced from the
[Red Hat Cost Management API](https://console.redhat.com/api/cost-management/v1).
The date range is driven by the Grafana time picker.

Two installation variants are provided:

## `dashboard_native/` — JSONata (recommended)

Grafana queries the API **directly** using the Infinity datasource with a JSONata
expression. No external process needed.

```bash
cd dashboard_native
bash import_dashboard.sh
```

**Requires:** Grafana + Infinity plugin v3.x

## `dashboard_with_proxy/` — Flask proxy

A small Python server handles OAuth2 authentication and flattens the nested API
response. Grafana reads the flat JSON from the proxy.

```bash
cd dashboard_with_proxy
nohup python3 cost_proxy.py > /tmp/cost_proxy.log 2>&1 &
bash import_dashboard.sh
```

**Requires:** Grafana + Infinity plugin, Python 3.8+ (`flask`, `requests`)

## When to use which

| | Native (JSONata) | With Proxy |
|---|---|---|
| External dependencies | None | Python + Flask |
| OAuth2 credentials stored in | Grafana datasource | Proxy script |
| Works if Grafana can't reach the API | No | Yes (proxy on a host that can) |
| Extra processing (caching, filtering) | No | Easily extensible |
| Recommended for most users | **Yes** | For special cases |

See each directory's `README.md` for full details.
