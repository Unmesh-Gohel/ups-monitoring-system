"""Raritan-style JSON-RPC PDU mock (24 outlets). Dev/simulator only."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

APP_ENV = os.getenv("APP_ENV", "dev").lower()
if APP_ENV == "production":
    raise SystemExit("raritan-pdu-mock refuses to start when APP_ENV=production")

STATE_FILE = Path(os.getenv("SIM_STATE_FILE", "/shared/state/raritan-pdu.json"))
OUTLET_COUNT = 24


def _load_outlets() -> list[dict[str, Any]]:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    if STATE_FILE.exists():
        raw = json.loads(STATE_FILE.read_text(encoding="utf-8"))
        outlets = raw.get("outlets")
        if isinstance(outlets, list) and len(outlets) == OUTLET_COUNT:
            return outlets
    outlets = [
        {"id": i, "name": f"Outlet {i}", "state": "on", "amps": 0.1 * ((i % 5) + 1)}
        for i in range(1, OUTLET_COUNT + 1)
    ]
    _save_outlets(outlets)
    return outlets


def _save_outlets(outlets: list[dict[str, Any]]) -> None:
    base: dict[str, Any] = {}
    if STATE_FILE.exists():
        try:
            base = json.loads(STATE_FILE.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            base = {}
    base["outlets"] = outlets
    STATE_FILE.write_text(json.dumps(base, indent=2, sort_keys=True) + "\n", encoding="utf-8")


app = FastAPI(title="Raritan PDU mock", version="0.1.0")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/rpc")
async def rpc(request: Request) -> JSONResponse:
    payload = await request.json()
    method = payload.get("method")
    req_id = payload.get("id")
    params = payload.get("params") or {}

    outlets = _load_outlets()

    if method in {"pdumodel.Outlet.get_meta", "outlet.list"}:
        return JSONResponse(
            {"jsonrpc": "2.0", "id": req_id, "result": outlets}
        )

    if method in {"pdumodel.Outlet.getState", "outlet.getState"}:
        outlet_id = int(params.get("outlet_id") or params.get("id") or 0)
        match = next((o for o in outlets if o["id"] == outlet_id), None)
        if not match:
            return JSONResponse(
                {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "error": {"code": -32000, "message": "unknown outlet"},
                }
            )
        return JSONResponse({"jsonrpc": "2.0", "id": req_id, "result": match})

    if method in {"pdumodel.Outlet.setPowerState", "outlet.set"}:
        outlet_id = int(params.get("outlet_id") or params.get("id") or 0)
        action = str(params.get("action") or params.get("state") or "").lower()
        match = next((o for o in outlets if o["id"] == outlet_id), None)
        if not match:
            return JSONResponse(
                {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "error": {"code": -32000, "message": "unknown outlet"},
                }
            )
        sim = {}
        if STATE_FILE.exists():
            sim = json.loads(STATE_FILE.read_text(encoding="utf-8"))
        fail_map = sim.get("outlet_fail_after_reboot") or {}
        if action in {"cycle", "reboot"} and fail_map.get(str(outlet_id)):
            match["state"] = "off"
        elif action in {"on", "power_on", "1"}:
            match["state"] = "on"
        elif action in {"off", "power_off", "0"}:
            match["state"] = "off"
        elif action in {"cycle", "reboot"}:
            match["state"] = "on"
        else:
            return JSONResponse(
                {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "error": {"code": -32602, "message": "invalid action"},
                }
            )
        _save_outlets(outlets)
        return JSONResponse({"jsonrpc": "2.0", "id": req_id, "result": match})

    return JSONResponse(
        {
            "jsonrpc": "2.0",
            "id": req_id,
            "error": {"code": -32601, "message": f"method not found: {method}"},
        }
    )
