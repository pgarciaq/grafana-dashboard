#!/usr/bin/env bash
# --------------------------------------------------------------------------
# import_dashboard.sh — Configure a Prometheus datasource in Grafana and
#                       import the json_exporter-based Cost Management dashboard.
#
# Prerequisites:
#   - Grafana running on localhost:3000 (admin/redhat)
#   - Prometheus running on localhost:9090
#   - json_exporter running on localhost:7979
#   - curl and jq installed
# --------------------------------------------------------------------------
set -euo pipefail

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-redhat}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
DS_NAME="Prometheus (Cost Management)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

g() {
  local method=$1 path=$2
  shift 2
  curl -sf -X "$method" \
    -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
    -H "Content-Type: application/json" \
    "$@" "${GRAFANA_URL}${path}"
}

echo "==> Checking Grafana connectivity..."
if ! g GET /api/health > /dev/null 2>&1; then
  echo "ERROR: Cannot reach Grafana at ${GRAFANA_URL}" >&2
  echo "       Set GRAFANA_URL if it runs on a different host/port." >&2
  exit 1
fi
echo "    Grafana is up."

# ---- Datasource ----
echo "==> Configuring Prometheus datasource..."
DS_UID=""
EXISTING=$(g GET "/api/datasources/name/$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$DS_NAME")" 2>/dev/null || true)
if [ -n "$EXISTING" ] && echo "$EXISTING" | jq -e '.uid' > /dev/null 2>&1; then
  DS_UID=$(echo "$EXISTING" | jq -r '.uid')
  echo "    Datasource already exists (uid=${DS_UID}). Updating..."
  g PUT "/api/datasources/uid/${DS_UID}" -d @- > /dev/null <<EOF
{
  "name": "${DS_NAME}",
  "type": "prometheus",
  "access": "proxy",
  "url": "${PROMETHEUS_URL}",
  "uid": "${DS_UID}",
  "jsonData": {
    "httpMethod": "POST",
    "timeInterval": "15m"
  }
}
EOF
else
  echo "    Creating new datasource..."
  RESULT=$(g POST /api/datasources -d @- <<EOF
{
  "name": "${DS_NAME}",
  "type": "prometheus",
  "access": "proxy",
  "url": "${PROMETHEUS_URL}",
  "jsonData": {
    "httpMethod": "POST",
    "timeInterval": "15m"
  }
}
EOF
)
  DS_UID=$(echo "$RESULT" | jq -r '.datasource.uid')
fi
echo "    Datasource uid: ${DS_UID}"

# ---- Dashboard ----
echo "==> Importing dashboard..."
DASHBOARD_FILE="${SCRIPT_DIR}/dashboard.json"
if [ ! -f "$DASHBOARD_FILE" ]; then
  echo "ERROR: ${DASHBOARD_FILE} not found" >&2
  exit 1
fi

PAYLOAD=$(sed "s/PLACEHOLDER_DS_UID/${DS_UID}/g" "$DASHBOARD_FILE")
RESULT=$(echo "$PAYLOAD" | g POST /api/dashboards/db -d @-)
DASH_URL=$(echo "$RESULT" | jq -r '.url // empty')

if [ -n "$DASH_URL" ]; then
  echo "    Dashboard imported: ${GRAFANA_URL}${DASH_URL}"
else
  echo "    Dashboard import response:"
  echo "$RESULT" | jq .
fi

echo ""
echo "Done. Open Grafana and select the dashboard:"
echo "  ${GRAFANA_URL}${DASH_URL:-/d/ocp-costs-json-exporter}"
echo ""
echo "NOTE: The dashboard will show data only after Prometheus has scraped"
echo "      json_exporter at least once (first scrape may take up to 15 min)."
