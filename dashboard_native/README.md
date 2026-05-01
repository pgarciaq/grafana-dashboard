# Dashboard: Native (JSONata)

Grafana queries the Cost Management API **directly** using the Infinity datasource
with a JSONata expression to flatten the nested response. No external proxy needed.

## Architecture

```
Grafana  ──(Infinity + OAuth2)──►  console.redhat.com/api/cost-management/v1
                                        │
                                        │  JSONata flattens in-place:
                                        │  $.data.projects.values.{"date", "project", "cost"}
                                        ▼
                                   Flat table → Partition by project → Time series
```

## Prerequisites

- Grafana with the **Infinity datasource plugin** (`yesoreyeram-infinity-datasource` v3.x)
- A Red Hat service account with access to Cost Management

## Configuring credentials

The script reads credentials from environment variables, falling back to
placeholder values in the script (lines 22–23):

```bash
export COSTMGMT_CLIENT_ID="your-client-id"
export COSTMGMT_CLIENT_SECRET="your-client-secret"
```

Alternatively, edit `import_dashboard.sh` directly and replace the
`YOUR_CLIENT_ID` / `YOUR_CLIENT_SECRET` placeholders on lines 22–23.

Either way, the credentials are passed to Grafana's Infinity datasource
OAuth2 configuration during import. After import, they are stored in
**Grafana's internal database** — they are not written to `dashboard.json`
or any other tracked file.

## Quick start

```bash
# Option A: environment variables (recommended)
export COSTMGMT_CLIENT_ID="your-client-id"
export COSTMGMT_CLIENT_SECRET="your-client-secret"
bash import_dashboard.sh                                       # localhost:3000, admin/redhat
bash import_dashboard.sh http://grafana:3000 admin password    # custom

# Option B: edit the script directly
vi import_dashboard.sh   # replace placeholders on lines 22–23
bash import_dashboard.sh
```

Then open the URL printed by the script.

## What the import script does

1. Creates (or updates) an Infinity datasource named **Cost Management API** with:
   - OAuth2 client credentials (from the `CLIENT_ID` / `CLIENT_SECRET` in the script)
   - Token URL: `https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token`
   - Allowed hosts: `console.redhat.com`, `sso.redhat.com`
2. Imports `dashboard.json`, wiring it to the datasource

## Time range

The API query uses `start_date=${__from:date:YYYY-MM-DD}&end_date=${__to:date:YYYY-MM-DD}`,
so the data automatically matches whatever you select in the Grafana time picker.

## JSONata expression

```jsonata
$.data.projects.values.{"date": date, "project": project, "cost": cost.total.value}
```

### Other cost fields you can use

| JSONata path | Meaning |
|---|---|
| `cost.total.value` | Total cost (default) |
| `cost.raw.value` | Raw cost (no markup) |
| `cost.markup.value` | Markup only |
| `cost.usage.value` | Usage cost only |
| `infrastructure.total.value` | Infrastructure cost only |
| `supplementary.total.value` | Supplementary cost only |
