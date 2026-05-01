"""
Tiny proxy that flattens the nested Cost Management API response
into a simple [{date, project, cost}] JSON array for Grafana.

Accepts start_date and end_date query params (YYYY-MM-DD) so the
Grafana time picker controls the date range automatically.
"""
from flask import Flask, jsonify, request
import requests
import time

app = Flask(__name__)

CLIENT_ID = "YOUR_CLIENT_ID"
CLIENT_SECRET = "YOUR_CLIENT_SECRET"
TOKEN_URL = "https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token"
API_BASE = "https://console.redhat.com/api/cost-management/v1/reports/openshift/costs/"

_token_cache = {}


def get_token():
    if _token_cache.get("expires_at", 0) > time.time() + 30:
        return _token_cache["token"]
    r = requests.post(TOKEN_URL, data={
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "grant_type": "client_credentials",
        "scope": "api.console",
    }, timeout=15)
    r.raise_for_status()
    d = r.json()
    _token_cache["token"] = d["access_token"]
    _token_cache["expires_at"] = time.time() + d.get("expires_in", 300)
    return _token_cache["token"]


@app.route("/ocp-costs-flat")
def ocp_costs_flat():
    start_date = request.args.get("start_date")
    end_date = request.args.get("end_date")

    token = get_token()
    params = {
        "filter[resolution]": "daily",
        "group_by[project]": "*",
    }
    if start_date and end_date:
        params["start_date"] = start_date
        params["end_date"] = end_date
    else:
        params["filter[time_scope_units]"] = "day"
        params["filter[time_scope_value]"] = "-30"

    r = requests.get(
        API_BASE, headers={"Authorization": f"Bearer {token}"}, params=params, timeout=60
    )
    r.raise_for_status()
    data = r.json()

    rows = []
    for day in data.get("data", []):
        date_str = day.get("date", "")
        for proj_item in day.get("projects", []):
            project = proj_item.get("project", "unknown")
            for val in proj_item.get("values", []):
                cost = (
                    val.get("cost", {})
                       .get("total", {})
                       .get("value", 0) or 0
                )
                rows.append({"date": date_str, "project": project, "cost": cost})

    resp = jsonify(rows)
    resp.headers["Access-Control-Allow-Origin"] = "*"
    return resp


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5050, debug=False)
