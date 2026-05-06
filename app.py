from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path
from typing import Any, Optional

import yaml
from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

DEFAULT_CONFIG_PATH = Path(__file__).with_name("config.yaml")


class AppConfig(BaseModel):
    api_token: Optional[str] = None
    fullpageos_path: str = "/boot/firmware/fullpageos.txt"
    allowed_ssh_hosts: list[str] = Field(default_factory=list)
    allowed_ssh_users: list[str] = Field(default_factory=list)
    allowed_ssh_commands: list[str] = Field(default_factory=list)


class FullpageosUpdate(BaseModel):
    content: str


class SshRequest(BaseModel):
    host: str
    user: Optional[str] = None
    command: str
    port: int = 22
    identity_file: Optional[str] = None


def load_config() -> AppConfig:
    config_path = Path(os.getenv("PICONTROL_CONFIG", DEFAULT_CONFIG_PATH))
    if not config_path.exists():
        return AppConfig()
    raw = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
    return AppConfig(**raw)


config = load_config()
app = FastAPI(title="Pi Control Service", version="0.1.0")


def require_token(x_api_token: Optional[str] = Header(default=None)) -> None:
    if not config.api_token:
        return
    if x_api_token != config.api_token:
        raise HTTPException(status_code=401, detail="Invalid API token")


def validate_ssh_request(payload: SshRequest) -> None:
    if config.allowed_ssh_hosts and payload.host not in config.allowed_ssh_hosts:
        raise HTTPException(status_code=403, detail="Host not allowed")
    if payload.user and config.allowed_ssh_users and payload.user not in config.allowed_ssh_users:
        raise HTTPException(status_code=403, detail="User not allowed")
    if config.allowed_ssh_commands:
        allowed = any(re.fullmatch(pattern, payload.command) for pattern in config.allowed_ssh_commands)
        if not allowed:
            raise HTTPException(status_code=403, detail="Command not allowed")


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/fullpageos", dependencies=[Depends(require_token)])
async def get_fullpageos() -> dict[str, str]:
    path = Path(config.fullpageos_path)
    if not path.exists():
        raise HTTPException(status_code=404, detail="fullpageos.txt not found")
    return {"content": path.read_text(encoding="utf-8")}


@app.put("/fullpageos", dependencies=[Depends(require_token)])
async def set_fullpageos(payload: FullpageosUpdate) -> dict[str, str]:
    path = Path(config.fullpageos_path)
    try:
        path.write_text(payload.content, encoding="utf-8")
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail="Permission denied") from exc
    return {"status": "updated"}


@app.post("/reboot", dependencies=[Depends(require_token)])
async def reboot_pi() -> dict[str, Any]:
    process = subprocess.run(
        ["systemctl", "reboot"], capture_output=True, text=True, check=False
    )
    if process.returncode != 0:
        detail = (process.stderr or process.stdout).strip() or "Reboot failed"
        raise HTTPException(status_code=403, detail=detail)
    return {"status": "rebooting"}


@app.post("/ssh", dependencies=[Depends(require_token)])
async def run_ssh(payload: SshRequest) -> dict[str, Any]:
    validate_ssh_request(payload)
    target = f"{payload.user}@{payload.host}" if payload.user else payload.host
    args = [
        "ssh",
        "-p",
        str(payload.port),
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=accept-new",
    ]
    if payload.identity_file:
        args += ["-i", payload.identity_file]
    args += [target, payload.command]
    process = subprocess.run(args, capture_output=True, text=True, check=False, timeout=30)
    return {
        "stdout": process.stdout,
        "stderr": process.stderr,
        "returncode": process.returncode,
    }
