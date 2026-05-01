# OpenShift Daily Costs — json\_exporter + Prometheus

Grafana dashboard showing **OpenShift cost data per project**, collected via
[`json_exporter`](https://github.com/prometheus-community/json_exporter) and
stored in [Prometheus](https://prometheus.io).

## Architecture

```
Red Hat SSO                Cost Management API
     ^                           ^
     | OAuth2 client_credentials | Bearer token (automatic)
     |                           |
     +---- json_exporter :7979 --+
                  ^
                  | GET /probe?module=ocp_costs&target=<API_URL>
                  |
           Prometheus :9090
                  ^
                  | PromQL
                  |
            Grafana :3000
```

**How it works:**

1. Prometheus scrapes json\_exporter's `/probe` endpoint every 15 minutes,
   passing the Cost Management API URL as the `target` parameter.
2. json\_exporter fetches the API (handling OAuth2 token acquisition
   automatically via the built-in `oauth2` client config), parses the nested
   JSON response, and returns Prometheus-formatted metrics.
3. Prometheus stores the metrics as time series.
4. Grafana queries Prometheus via PromQL.

**No proxy or token-refresh script required.** json\_exporter v0.7+ (with
`prometheus/common` v0.67+) supports OAuth2 client credentials natively.

---

## Prerequisites

| Component | Version | Purpose |
|-----------|---------|---------|
| [json\_exporter](https://github.com/prometheus-community/json_exporter) | v0.7+ | Scrapes JSON API, returns Prometheus metrics |
| [Prometheus](https://prometheus.io/download/) | 2.x+ | Time-series storage and PromQL |
| [Grafana](https://grafana.com/grafana/download/) | 11.x+ | Dashboard visualization |

A **Red Hat service account** with access to Cost Management is also required.

### Configuring credentials

**Option A — environment variables + `envsubst`** (recommended, keeps the
config file clean):

```bash
export COSTMGMT_CLIENT_ID="your-client-id"
export COSTMGMT_CLIENT_SECRET="your-client-secret"
envsubst < json_exporter_config.yml > /tmp/json_exporter_config.yml
json_exporter --config.file=/tmp/json_exporter_config.yml
```

**Option B — edit the file directly:**

Edit `json_exporter_config.yml` and replace the placeholder values in the
`oauth2` section (lines 17–18):

```yaml
      oauth2:
        client_id: "your-client-id"
        client_secret: "your-client-secret"
```

json\_exporter reads the config file at startup and handles OAuth2 token
acquisition and renewal automatically. No credentials are stored in Grafana,
Prometheus, or `dashboard.json`.

---

## Setup

### 1. Configure credentials and start json\_exporter

```bash
# Set credentials via environment variables
export COSTMGMT_CLIENT_ID="your-client-id"
export COSTMGMT_CLIENT_SECRET="your-client-secret"

# Option A: binary (with envsubst)
envsubst < json_exporter_config.yml > /tmp/json_exporter_config.yml
json_exporter --config.file=/tmp/json_exporter_config.yml

# Option B: Docker / Podman (with envsubst)
envsubst < json_exporter_config.yml > /tmp/json_exporter_config.yml
docker run -d --name json-exporter \
  --network=host \
  -v "/tmp/json_exporter_config.yml:/config.yml:ro" \
  quay.io/prometheuscommunity/json-exporter \
  --config.file=/config.yml

# Option C: edit json_exporter_config.yml directly and skip envsubst
vi json_exporter_config.yml
json_exporter --config.file=json_exporter_config.yml
```

Verify it responds:

```bash
curl -s http://localhost:7979/metrics | head -5
```

### 2. Configure Prometheus

Add the scrape jobs from `prometheus_scrape.yml` to your existing
`prometheus.yml` under `scrape_configs:`, then reload Prometheus:

```bash
# If running via systemd:
sudo systemctl reload prometheus

# If running via Docker, restart the container or send SIGHUP:
kill -HUP $(pgrep prometheus)
```

After ~15 minutes, verify metrics are flowing:

```bash
curl -s 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=ocp_cost_total_usd' | python3 -m json.tool
```

### 3. Import the Grafana dashboard

```bash
bash import_dashboard.sh
```

This creates a Prometheus datasource in Grafana and imports the dashboard.
Open the URL printed at the end.

---

## How the data model works

> **Important:** Understanding this section is key to interpreting the
> dashboard correctly. The json\_exporter variant behaves differently from the
> native and proxy variants.

The Cost Management API returns daily costs with a `date` field
(e.g., `2026-04-01`, `2026-04-02`, ...). json\_exporter converts these into
Prometheus metrics, but **all metrics get the same timestamp** — the Prometheus
scrape time. The API `date` becomes a Prometheus **label**, not a native
timestamp.

This means:

- A standard Grafana **time series panel** cannot plot daily costs over time,
  because all data points share the same Prometheus timestamp.
- Instead, the dashboard uses a **bar chart** with the `date` label as the
  X-axis (via Grafana's `groupingToMatrix` transformation). This correctly
  shows one bar per day regardless of when Prometheus scraped the data.
- The **stat**, **pie**, and **table** panels use **instant queries**
  (evaluated at `time=now`), so they always return the latest scraped values
  and are **unaffected by the Grafana time picker**.

### The "Cost Trend" panel starts empty — this is normal

The **"Cost Trend (accumulates over scrape history)"** panel is a time series
that plots the `ocp_cost_total_usd` metric over **Prometheus scrape timestamps**
(wall-clock time), NOT over the API's daily `date` values.

- **On day one**, this panel will show only a single data point (or a short
  flat line) at today's timestamp. **This is expected.**
- Over the following days, as Prometheus scrapes every 15 minutes, new data
  points accumulate and the panel gradually builds a trend line.
- After a week or more, you'll see a meaningful visualization of how total
  cost evolves over real time.

This is fundamentally different from the native/proxy variants, where the
"Cost Trend" panel shows daily total cost from the API (one point per day,
driven by the Grafana time picker). The json\_exporter variant tracks
*scrape history* — useful for monitoring when cost data changes, but not
for viewing daily breakdowns (use the bar chart for that).

### API time range

The Prometheus scrape config requests **the last 30 days** of daily data from
the API (`filter[time_scope_value]=-30&filter[time_scope_units]=day`). This
ensures the bar chart always shows ~30 bars. To change the window, edit the
`target` URL in `prometheus_scrape.yml`.

---

## Metrics reference

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `ocp_cost_total_usd` | gauge | — | Total cost across all projects (last 30 days) |
| `ocp_project_cost_total_usd` | gauge | `project`, `date` | Total cost per project per day |
| `ocp_project_cost_raw_usd` | gauge | `project`, `date` | Raw (infrastructure) cost per project per day |
| `ocp_project_cost_markup_usd` | gauge | `project`, `date` | Markup cost per project per day |
| `ocp_project_cost_usage_usd` | gauge | `project`, `date` | Usage (supplementary) cost per project per day |

## Dashboard panels

| Panel | Type | PromQL | Description |
|-------|------|--------|-------------|
| Daily Cost per Project | Bar chart | `ocp_project_cost_total_usd` | Stacked bars (one per day, segments per project) using the `date` label as X-axis |
| Total Cost This Month | Stat | `ocp_cost_total_usd` | Single number, color-coded by threshold |
| Cost by Project | Pie chart | `sum by (project) (ocp_project_cost_total_usd)` | Proportional breakdown |
| Cost Trend (accumulates over scrape history) | Time series | `ocp_cost_total_usd` | **Starts empty** — accumulates data points over days as Prometheus scrapes (see [note above](#the-cost-trend-panel-starts-empty--this-is-normal)) |
| Daily Cost Detail | Table | `ocp_project_cost_total_usd` | Sortable/filterable table with date, project, cost |

---

## Useful PromQL queries

```promql
# Total cost for the last 30 days
ocp_cost_total_usd

# Total per project (summed across all days)
sum by (project) (ocp_project_cost_total_usd)

# Top 5 most expensive projects
topk(5, sum by (project) (ocp_project_cost_total_usd))

# Cost breakdown (raw vs markup vs usage) for a specific project
ocp_project_cost_raw_usd{project="my-namespace"}
ocp_project_cost_markup_usd{project="my-namespace"}
ocp_project_cost_usage_usd{project="my-namespace"}

# Cost for a specific day
ocp_project_cost_total_usd{date="2026-04-15"}
```

---

## Alerting examples

Because data lives in Prometheus, you can define alerts in Alertmanager:

```yaml
# Alert when total cost exceeds $10,000
groups:
  - name: cost-management
    rules:
      - alert: HighMonthlyCost
        expr: ocp_cost_total_usd > 10000
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "OpenShift cost (last 30 days) exceeds $10,000"
          description: "Current total: ${{ $value | printf \"%.2f\" }}"

      - alert: ProjectCostSpike
        expr: sum by (project) (ocp_project_cost_total_usd) > 2000
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "Project {{ $labels.project }} cost exceeds $2,000"
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `ocp_cost_total_usd` not in Prometheus | json\_exporter not scraped yet | Wait 15 min, or check `http://localhost:9090/targets` |
| Probe returns 401 | OAuth2 credentials wrong or expired | Update `json_exporter_config.yml` oauth2 section |
| Probe returns 403 | Service account lacks Cost Management access | Verify permissions on console.redhat.com |
| Dashboard shows "No data" | Prometheus datasource misconfigured | Re-run `import_dashboard.sh`, check datasource in Grafana |
| Bar chart shows only 1 bar | API returns only current day's data | Verify the target URL uses `time_scope_value=-30&time_scope_units=day` |
| `group_by` ignored, no per-project data | URL `&` split across Prometheus params | Use `params.target` in Prometheus config, not `static_configs.targets` + relabel (see `prometheus_scrape.yml`) |
| All cost values are $0 | No cost model assigned in Cost Management | Assign a cost model with rates to the OCP source |
| Panels show stale data after Prometheus restart | Prometheus TSDB data was lost | Mount a persistent volume for Prometheus data (`-v /path:/prometheus`) |

### Data model note: Grafana time picker vs bar chart

The **Grafana time picker does not affect** the bar chart, stat, pie, or table
panels. These panels use instant queries (evaluated at `time=now`) and get
their date range from the API response's `date` labels, not from Prometheus
timestamps. Only the "Cost Trend" time series panel is affected by the time
picker.

### Fallback: use the Flask proxy as json\_exporter target

If the nested JSONPath `{.data[*].projects[*].values[*]}` does not work with
your json\_exporter version, you can point json\_exporter at the Flask proxy
from `dashboard_with_proxy/` instead. The proxy returns flat JSON, simplifying
the metric extraction:

1. Start the Flask proxy (`../dashboard_with_proxy/cost_proxy.py`).
2. Replace the json\_exporter config metrics section with a flat path.
3. Update the Prometheus target URL to `http://localhost:5050/ocp-costs-flat`.
