"""Dev-only simulator controller for PowerWatch Phase 0."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Literal

from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field

APP_ENV = os.getenv("APP_ENV", "dev").lower()
if APP_ENV == "production":
    raise SystemExit("sim-controller refuses to start when APP_ENV=production")

STATE_DIR = Path(os.getenv("SIM_STATE_DIR", "/shared/state"))
DEVICES = (
    "eaton-ups",
    "apc-ups",
    "apc-pdu",
    "raritan-pdu",
    "nut-ups",
)

DEFAULT_STATE: dict[str, Any] = {
    "on_battery": False,
    "runtime_minutes": 20,
    "battery_temp_c": 28,
    "battery_replace": False,
    "overload": False,
    "silent": False,
    "outlet_fail_after_reboot": {},
}


def _state_path(device_id: str) -> Path:
    return STATE_DIR / f"{device_id}.json"


def _read_state(device_id: str) -> dict[str, Any]:
    path = _state_path(device_id)
    if not path.exists():
        return dict(DEFAULT_STATE)
    return json.loads(path.read_text(encoding="utf-8"))


def _write_state(device_id: str, state: dict[str, Any]) -> dict[str, Any]:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    path = _state_path(device_id)
    path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return state


def _ensure_defaults() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    for device_id in DEVICES:
        path = _state_path(device_id)
        if not path.exists():
            _write_state(device_id, dict(DEFAULT_STATE))


_ensure_defaults()

app = FastAPI(title="PowerWatch sim-controller", version="0.1.0", docs_url="/docs")


class ScenarioRequest(BaseModel):
    device_id: Literal[
        "eaton-ups",
        "apc-ups",
        "apc-pdu",
        "raritan-pdu",
        "nut-ups",
        "all",
    ] = "all"
    outlet_id: str | None = Field(default=None, description="Required for outlet_fail_after_reboot")


def _iter_targets(device_id: str) -> list[str]:
    if device_id == "all":
        return list(DEVICES)
    return [device_id]


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "app_env": APP_ENV}


@app.get("/state")
def get_all_state() -> dict[str, Any]:
    return {device_id: _read_state(device_id) for device_id in DEVICES}


@app.get("/state/{device_id}")
def get_state(device_id: str) -> dict[str, Any]:
    if device_id not in DEVICES:
        raise HTTPException(status_code=404, detail="unknown device")
    return _read_state(device_id)


@app.post("/scenarios/cut-power")
def cut_power(body: ScenarioRequest) -> dict[str, Any]:
    updated: dict[str, Any] = {}
    for device_id in _iter_targets(body.device_id):
        state = _read_state(device_id)
        state["on_battery"] = True
        state["runtime_minutes"] = max(1, int(state.get("runtime_minutes", 20)) - 1)
        updated[device_id] = _write_state(device_id, state)
    return {"scenario": "cut-power", "devices": updated}


@app.post("/scenarios/restore-power")
def restore_power(body: ScenarioRequest) -> dict[str, Any]:
    updated: dict[str, Any] = {}
    for device_id in _iter_targets(body.device_id):
        state = _read_state(device_id)
        state["on_battery"] = False
        state["runtime_minutes"] = 20
        updated[device_id] = _write_state(device_id, state)
    return {"scenario": "restore-power", "devices": updated}


@app.post("/scenarios/overheat")
def overheat(body: ScenarioRequest) -> dict[str, Any]:
    updated: dict[str, Any] = {}
    for device_id in _iter_targets(body.device_id):
        state = _read_state(device_id)
        state["battery_temp_c"] = 42
        updated[device_id] = _write_state(device_id, state)
    return {"scenario": "overheat", "devices": updated}


@app.post("/scenarios/battery-replace")
def battery_replace(body: ScenarioRequest) -> dict[str, Any]:
    updated: dict[str, Any] = {}
    for device_id in _iter_targets(body.device_id):
        state = _read_state(device_id)
        state["battery_replace"] = True
        updated[device_id] = _write_state(device_id, state)
    return {"scenario": "battery-replace", "devices": updated}


@app.post("/scenarios/overload")
def overload(body: ScenarioRequest) -> dict[str, Any]:
    updated: dict[str, Any] = {}
    for device_id in _iter_targets(body.device_id):
        state = _read_state(device_id)
        state["overload"] = True
        updated[device_id] = _write_state(device_id, state)
    return {"scenario": "overload", "devices": updated}


@app.post("/scenarios/silence")
def silence(body: ScenarioRequest) -> dict[str, Any]:
    updated: dict[str, Any] = {}
    for device_id in _iter_targets(body.device_id):
        state = _read_state(device_id)
        state["silent"] = True
        updated[device_id] = _write_state(device_id, state)
    return {"scenario": "silence", "devices": updated}


@app.post("/scenarios/unsilence")
def unsilence(body: ScenarioRequest) -> dict[str, Any]:
    updated: dict[str, Any] = {}
    for device_id in _iter_targets(body.device_id):
        state = _read_state(device_id)
        state["silent"] = False
        updated[device_id] = _write_state(device_id, state)
    return {"scenario": "unsilence", "devices": updated}


@app.post("/scenarios/outlet-fail-after-reboot")
def outlet_fail_after_reboot(body: ScenarioRequest) -> dict[str, Any]:
    if not body.outlet_id:
        raise HTTPException(status_code=400, detail="outlet_id is required")
    if body.device_id == "all":
        raise HTTPException(status_code=400, detail="pick a single device_id")
    state = _read_state(body.device_id)
    fails = dict(state.get("outlet_fail_after_reboot") or {})
    fails[body.outlet_id] = True
    state["outlet_fail_after_reboot"] = fails
    return {
        "scenario": "outlet-fail-after-reboot",
        "devices": {body.device_id: _write_state(body.device_id, state)},
    }


@app.post("/scenarios/reset")
def reset(body: ScenarioRequest) -> dict[str, Any]:
    updated: dict[str, Any] = {}
    for device_id in _iter_targets(body.device_id):
        updated[device_id] = _write_state(device_id, dict(DEFAULT_STATE))
    return {"scenario": "reset", "devices": updated}


@app.get("/", response_class=HTMLResponse)
def index() -> str:
    buttons = [
        ("cut-power", "Cut input power"),
        ("restore-power", "Restore power"),
        ("overheat", "Overheat battery"),
        ("battery-replace", "Flag battery replace"),
        ("overload", "Overload"),
        ("silence", "Stop answering"),
        ("unsilence", "Resume answering"),
        ("reset", "Reset all state"),
    ]
    rows = "\n".join(
        f'<button hx-post="/scenarios/{action}" onclick="run(\'{action}\')">{label}</button>'
        for action, label in buttons
    )
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <title>PowerWatch sim-controller</title>
  <style>
    body {{ font-family: Georgia, serif; margin: 2rem; background: #0f1714; color: #e7f0ea; }}
    button {{ margin: 0.25rem; padding: 0.6rem 1rem; cursor: pointer; }}
    pre {{ background: #1b2a24; padding: 1rem; overflow: auto; }}
  </style>
</head>
<body>
  <h1>PowerWatch sim-controller</h1>
  <p>Dev-only scenario controls. Refuses to start when APP_ENV=production.</p>
  <div>{rows}</div>
  <h2>State</h2>
  <pre id="state">loading…</pre>
  <script>
    async function refresh() {{
      const res = await fetch('/state');
      document.getElementById('state').textContent = JSON.stringify(await res.json(), null, 2);
    }}
    async function run(action) {{
      await fetch('/scenarios/' + action, {{
        method: 'POST',
        headers: {{'Content-Type': 'application/json'}},
        body: JSON.stringify({{device_id: 'all'}})
      }});
      await refresh();
    }}
    refresh();
  </script>
</body>
</html>"""
