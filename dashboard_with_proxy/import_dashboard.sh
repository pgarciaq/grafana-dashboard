#!/usr/bin/env bash
# import_dashboard.sh
#
# Configures the Infinity datasource in Grafana and imports the
# "OpenShift Daily Costs by Project (proxy)" dashboard.
#
# This variant uses a local Flask proxy (cost_proxy.py) that handles
# OAuth2 authentication and JSON flattening. The Infinity datasource
# only needs to reach the proxy — no OAuth2 config needed on the
# datasource itself.
#
# Usage:
#   bash import_dashboard.sh [GRAFANA_URL] [USER] [PASSWORD]
#
# Defaults:
#   GRAFANA_URL = http://localhost:3000
#   USER        = admin
#   PASSWORD    = redhat

set -euo pipefail

GRAFANA="${1:-http://localhost:3000}"
GF_USER="${2:-admin}"
GF_PASS="${3:-redhat}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AUTH="${GF_USER}:${GF_PASS}"

gf_get()  { curl -sf -u "$AUTH" "$GRAFANA$1"; }
gf_post() { curl -sf -X POST  -u "$AUTH" -H "Content-Type: application/json" -d "$2" "$GRAFANA$1"; }
gf_put()  { curl -sf -X PUT   -u "$AUTH" -H "Content-Type: application/json" -d "$2" "$GRAFANA$1"; }

echo "==> Grafana: $GRAFANA"

# ── 0. Verify the proxy is running ────────────────────────────────────────────
echo "==> Checking proxy at http://localhost:5050..."
if ! curl -sf http://localhost:5050/health > /dev/null 2>&1; then
    echo "ERROR: proxy is not running. Start it first:" >&2
    echo "  nohup python3 $SCRIPT_DIR/cost_proxy.py > /tmp/cost_proxy.log 2>&1 &" >&2
    exit 1
fi
echo "    proxy is healthy"

# ── 1. Upsert the Infinity datasource ─────────────────────────────────────────
DS_NAME="Cost Management API (proxy)"
DS_NAME_ENC="Cost%20Management%20API%20%28proxy%29"

echo "==> Configuring '$DS_NAME' datasource..."

EXISTING_UID=$(gf_get "/api/datasources/name/$DS_NAME_ENC" 2>/dev/null \
               | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null || true)

DS_PAYLOAD=$(python3 - <<PYEOF
import json

payload = {
    "name": "$DS_NAME",
    "type": "yesoreyeram-infinity-datasource",
    "access": "proxy",
    "jsonData": {
        "allowedHosts": [
            "localhost:5050",
            "http://localhost:5050",
            "127.0.0.1:5050",
            "http://127.0.0.1:5050"
        ],
    },
}
print(json.dumps(payload))
PYEOF
)

if [ -n "$EXISTING_UID" ]; then
    echo "    datasource exists (uid=$EXISTING_UID), updating..."
    FULL_DS=$(gf_get "/api/datasources/uid/$EXISTING_UID")
    MERGED=$(python3 - <<PYEOF
import json

full  = json.loads('''$FULL_DS''')
patch = json.loads('''$DS_PAYLOAD''')

jd = full.get("jsonData", {}) or {}
jd.update(patch["jsonData"])
full["jsonData"] = jd

print(json.dumps(full))
PYEOF
    )
    gf_put "/api/datasources/uid/$EXISTING_UID" "$MERGED" \
        | python3 -c "import sys,json; r=json.load(sys.stdin); print('    ' + r.get('message', str(r)))"
    DS_UID="$EXISTING_UID"
else
    echo "    creating new datasource..."
    RESULT=$(gf_post "/api/datasources" "$DS_PAYLOAD")
    DS_UID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('datasource',{}).get('uid',''))")
    echo "    created uid=$DS_UID"
fi

# ── 2. Import the dashboard ────────────────────────────────────────────────────
echo "==> Importing dashboard from $SCRIPT_DIR/dashboard.json..."

DASHBOARD_JSON=$(cat "$SCRIPT_DIR/dashboard.json")

IMPORT_PAYLOAD=$(python3 - <<PYEOF
import json

dash = json.loads('''$DASHBOARD_JSON''')

# Replace the placeholder datasource UID with the one we just created/found
dash_str = json.dumps(dash).replace("PLACEHOLDER_DS_UID", "$DS_UID")
dash = json.loads(dash_str)

dash["version"] = 0
dash["id"] = None

payload = {
    "dashboard": dash,
    "overwrite": True,
    "folderId": 0,
    "inputs": [],
}
print(json.dumps(payload))
PYEOF
)

RESULT=$(gf_post "/api/dashboards/db" "$IMPORT_PAYLOAD")
STATUS=$(echo "$RESULT" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('status','unknown'))")
URL=$(echo "$RESULT"    | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('url',''))")

if [ "$STATUS" = "success" ]; then
    echo "==> Dashboard imported successfully!"
    echo "    URL: $GRAFANA$URL"
else
    echo "ERROR: import failed: $RESULT" >&2
    exit 1
fi

echo ""
echo "Done. Open the dashboard at the URL above."
