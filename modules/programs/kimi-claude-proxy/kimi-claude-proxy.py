#!/usr/bin/env python3
"""
Claude Code ↔ Kimi For Coding subscription proxy.

Acts as a local Anthropic-compatible endpoint for Claude Code. Forwards to
api.kimi.com/coding/v1, handling two gaps in Moonshot's Claude-Code-support:

1. Moonshot doesn't implement GET /v1/models/{id} (only /v1/models list),
   and Claude Code requires per-model-detail for validation. We fake it.
2. The kimi-code OAuth access_token lives 15 minutes. We refresh it using
   the refresh_token whenever it's within 2 minutes of expiry, storing the
   rotated tokens back into ~/.kimi/credentials/kimi-code.json (compatible
   with how kimi-cli manages the same file).

Usage:
    kimi-claude-proxy.py [--port 8787] [--verbose]

Moonshot explicitly names Claude Code as a supported client (per the 403
response on /chat/completions: "available for Coding Agents such as Kimi CLI,
Claude Code, Roo Code, Kilo Code, etc."), so this is within the spirit of
the subscription. File an issue if they ever implement /v1/models/{id} —
then this whole proxy becomes obsolete.
"""
import argparse
import asyncio
import json
import logging
import os
import sys
import time
from pathlib import Path

from aiohttp import web, ClientSession, ClientTimeout

KIMI_UPSTREAM = "https://api.kimi.com/coding/v1"
OAUTH_HOST = "https://auth.kimi.com"
CLIENT_ID = "17e5f671-d194-4dfb-9706-5516cb48c098"
CRED_PATH = Path.home() / ".kimi" / "credentials" / "kimi-code.json"
REFRESH_THRESHOLD_S = 120  # refresh if access_token expires within N seconds

log = logging.getLogger("kimi-claude-proxy")
_refresh_lock = asyncio.Lock()


async def load_creds() -> dict:
    return json.loads(CRED_PATH.read_text())


async def save_creds(creds: dict) -> None:
    tmp = CRED_PATH.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(creds, indent=2))
    os.chmod(tmp, 0o600)
    os.replace(tmp, CRED_PATH)


async def get_fresh_token(session: ClientSession) -> str:
    """Return a valid access_token, refreshing if close to expiry."""
    async with _refresh_lock:
        creds = await load_creds()
        remaining = creds["expires_at"] - time.time()
        if remaining > REFRESH_THRESHOLD_S:
            return creds["access_token"]
        log.info("token expires in %.0fs, refreshing", remaining)
        async with session.post(
            f"{OAUTH_HOST}/api/oauth/token",
            data={
                "client_id": CLIENT_ID,
                "grant_type": "refresh_token",
                "refresh_token": creds["refresh_token"],
            },
            timeout=ClientTimeout(total=15),
        ) as resp:
            body = await resp.text()
            if resp.status != 200:
                raise web.HTTPBadGateway(text=f"OAuth refresh failed: {resp.status} {body}")
            data = json.loads(body)
        creds["access_token"] = data["access_token"]
        # Moonshot may or may not rotate the refresh_token; use new one if returned.
        if data.get("refresh_token"):
            creds["refresh_token"] = data["refresh_token"]
        creds["expires_in"] = data["expires_in"]
        creds["expires_at"] = time.time() + data["expires_in"]
        if data.get("scope"):
            creds["scope"] = data["scope"]
        if data.get("token_type"):
            creds["token_type"] = data["token_type"]
        await save_creds(creds)
        log.info("token refreshed, new expiry in %ss", data["expires_in"])
        return creds["access_token"]


async def fake_model_detail(request: web.Request) -> web.Response:
    """Claude Code calls GET /v1/models/{id}?beta=true to validate model access.
    Moonshot returns 404; we fake it with kimi-for-coding's metadata regardless
    of the requested id, so Claude Code passes validation."""
    model_id = request.match_info.get("model_id", "kimi-for-coding")
    log.debug("fake model detail for %s", model_id)
    # Shape based on what Moonshot's /v1/models list returns for kimi-for-coding,
    # plus fields Anthropic-format clients commonly expect.
    return web.json_response({
        "id": "kimi-for-coding",
        "type": "model",
        "display_name": "Kimi-k2.6",
        "created_at": "2025-10-24T00:00:00Z",
        "context_length": 262144,
        "supports_reasoning": True,
        "supports_image_in": True,
        "supports_video_in": True,
    })


async def proxy(request: web.Request) -> web.StreamResponse:
    """Forward everything else upstream with a fresh bearer token."""
    session: ClientSession = request.app["client"]
    try:
        token = await get_fresh_token(session)
    except web.HTTPException:
        raise
    except Exception as exc:
        log.exception("token refresh error")
        return web.json_response({"error": {"message": str(exc)}}, status=502)

    path = request.rel_url.path
    # strip a leading /v1 if present (we mount at root and upstream also has /v1)
    upstream_path = path
    upstream_url = f"{KIMI_UPSTREAM.rstrip('/')}{upstream_path.replace('/v1', '', 1)}"
    # build headers — strip Authorization/auth-related and hop-by-hop; keep everything else
    skip = {"host", "authorization", "x-api-key", "content-length", "connection",
            "keep-alive", "proxy-authenticate", "proxy-authorization", "te",
            "trailers", "transfer-encoding", "upgrade"}
    headers = {k: v for k, v in request.headers.items() if k.lower() not in skip}
    headers["Authorization"] = f"Bearer {token}"

    body = await request.read()
    log.debug("%s %s → %s (body %d bytes)", request.method, path, upstream_url, len(body))

    async with session.request(
        request.method,
        upstream_url,
        params=request.rel_url.query,
        headers=headers,
        data=body if body else None,
        timeout=ClientTimeout(total=None, sock_connect=30, sock_read=None),
    ) as upstream_resp:
        # stream response back to client
        resp = web.StreamResponse(
            status=upstream_resp.status,
            headers={k: v for k, v in upstream_resp.headers.items()
                     if k.lower() not in {"content-encoding", "content-length", "transfer-encoding"}},
        )
        await resp.prepare(request)
        async for chunk in upstream_resp.content.iter_any():
            await resp.write(chunk)
        await resp.write_eof()
        return resp


async def on_startup(app: web.Application) -> None:
    app["client"] = ClientSession()


async def on_cleanup(app: web.Application) -> None:
    await app["client"].close()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--verbose", "-v", action="store_true")
    args = ap.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )

    if not CRED_PATH.exists():
        print(f"error: {CRED_PATH} not found — run `kimi` and `/login` first", file=sys.stderr)
        return 1

    app = web.Application(client_max_size=100 * 1024 * 1024)
    app.on_startup.append(on_startup)
    app.on_cleanup.append(on_cleanup)
    # Faked endpoint — matches GET /v1/models/{anything} (id may contain dots/dashes)
    app.router.add_get(r"/v1/models/{model_id:.+}", fake_model_detail)
    # Everything else proxies through
    app.router.add_route("*", "/{path:.*}", proxy)

    log.info("kimi-claude-proxy listening on %s:%d → %s", args.host, args.port, KIMI_UPSTREAM)
    web.run_app(app, host=args.host, port=args.port, print=None)
    return 0


if __name__ == "__main__":
    sys.exit(main())
