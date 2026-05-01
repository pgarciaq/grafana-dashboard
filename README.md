# OpenShift Daily Costs by Project — Grafana Dashboard

Time series dashboard showing **daily cost per OpenShift project**,
sourced from the Red Hat Cost Management API. The date range is driven by the
Grafana time picker (default: last 30 days).

## Files

| File | Purpose |
|------|---------|
| `dashboard.json` | Grafana dashboard definition (import into Grafana) |
| `import_dashboard.sh` | One-shot script to configure the datasource and import the dashboard |
| `README.md` | This file |

## Architecture

```
Grafana panel  ──(every 1 h)──►  console.redhat.com/api/cost-management/v1
                                   │
                                   │  OAuth2 client credentials via Red Hat SSO
                                   │  GET /reports/openshift/costs/?...&group_by[project]=*
                                   │
                                   ▼
                              JSON response (nested)
                                   │
                                   │  JSONata expression flattens in-place:
                                   │  $.data.projects.values.{"date", "project", "cost"}
                                   │
                                   ▼
                              Flat table → Partition by project → Time series
```

The panel uses the **Infinity datasource** with the **backend parser** and a **JSONata**
expression to flatten the nested `data[].projects[].values[]` structure directly into
`{date, project, cost}` rows — no intermediate proxy or server required.

### JSONata expression

```jsonata
$.data.projects.values.{"date": date, "project": project, "cost": cost.total.value}
```

This navigates into every `values` object across all days and projects, and extracts
the three fields needed for the time series.

---

## Prerequisites

- Grafana with the **Infinity datasource plugin** (`yesoreyeram-infinity-datasource` v3.x)
- A Red Hat service account with access to Cost Management

---

## Quick start

```bash
bash import_dashboard.sh
```

Then open http://localhost:3000/d/ocp-costs-by-project

To use a different Grafana instance:

```bash
bash import_dashboard.sh http://grafana-host:3000 admin password
```

---

## Step 1 — Configure the Infinity datasource

The datasource needs:

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
```

`import_dashboard.sh` applies all of this automatically via the Grafana API.

---

## Step 2 — Import the dashboard

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

## Customization

### Time range

The API query uses Grafana's built-in `${__from:date:YYYY-MM-DD}` and
`${__to:date:YYYY-MM-DD}` variables, so the data automatically matches whatever
you select in the Grafana time picker — last 7 days, last 90 days, custom range, etc.

### Change what cost is shown

The JSONata expression extracts `cost.total.value`. Other options:

| JSONata path | Meaning |
|--------------|---------|
| `cost.total.value` | Total cost (infrastructure + supplementary + markup + distributed) |
| `cost.raw.value` | Raw cost (no markup) |
| `cost.markup.value` | Markup only |
| `cost.usage.value` | Usage cost only |
| `infrastructure.total.value` | Infrastructure cost only |
| `supplementary.total.value` | Supplementary cost only |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| "URL not allowed" in Grafana | Missing allowed hosts | Re-run `import_dashboard.sh` or add hosts manually |
| Chart blank (very narrow time range) | Only 1 data point, can't draw a line | Widen the Grafana time picker to at least 2 days |
| 401 from API | Service account credentials expired | Update credentials in the Infinity datasource settings |
| All values $0 | No cost model assigned in Cost Management | Assign a cost model with rates to the OCP source |
