#!/usr/bin/env python3
"""
miniblue-kv-proxy — Option A translation shim for the official
Secrets Store CSI Driver provider-azure against the miniblue emulator.

Two listeners:

  * HTTPS :8443  — emulates the Azure Key Vault DATA PLANE.
      provider-azure calls  GET https://{vault}.vault.azure.net/secrets/{name}?api-version=7.x
      We read {vault} from the Host header's first label and forward to miniblue's
      native path  GET {MINIBLUE_KV_BASE}/keyvault/{vault}/secrets/{name}
      then NORMALISE the JSON so the azsecrets SDK can unmarshal it
      (enabled string->bool, RFC3339 timestamps->unix epoch).

  * HTTP  :8080  — emulates the Azure IMDS token endpoint.
      provider-azure (useVMManagedIdentity) calls
      GET http://169.254.169.254/metadata/identity/oauth2/token?resource=...
      (redirected here by an iptables DNAT rule). miniblue's KV plane ignores the
      bearer token, so we just mint an opaque, well-formed token response.

Everything is configurable via env:
  MINIBLUE_KV_BASE   default http://172.17.0.1:4566   (miniblue host-gateway:dataport)
  TLS_CERT_FILE      default /tls/tls.crt
  TLS_KEY_FILE       default /tls/tls.key
  HTTPS_PORT         default 8443
  HTTP_PORT          default 8080
"""
import calendar
import json
import os
import ssl
import sys
import threading
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

MINIBLUE_KV_BASE = os.environ.get("MINIBLUE_KV_BASE", "http://172.17.0.1:4566").rstrip("/")
TLS_CERT_FILE = os.environ.get("TLS_CERT_FILE", "/tls/tls.crt")
TLS_KEY_FILE = os.environ.get("TLS_KEY_FILE", "/tls/tls.key")
HTTPS_PORT = int(os.environ.get("HTTPS_PORT", "8443"))
HTTP_PORT = int(os.environ.get("HTTP_PORT", "8080"))


def log(msg):
    print(f"[{datetime.now(timezone.utc).isoformat()}] {msg}", flush=True)


def _to_epoch(value):
    """Best-effort convert a miniblue attribute value to a unix epoch int."""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return int(value)
    if isinstance(value, str):
        s = value.strip()
        if s.isdigit():
            return int(s)
        # RFC3339 / ISO8601, tolerate trailing Z
        try:
            dt = datetime.strptime(s.replace("Z", "+0000"), "%Y-%m-%dT%H:%M:%S%z")
            return calendar.timegm(dt.utctimetuple())
        except ValueError:
            try:
                dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
                return calendar.timegm(dt.utctimetuple())
            except ValueError:
                return None
    return None


def _to_bool(value, default=True):
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in ("true", "1", "yes")
    if isinstance(value, (int, float)):
        return value != 0
    return default


def normalise_secret(raw, vault, name):
    """Turn a miniblue secret payload into an azsecrets-compatible bundle."""
    src_attr = raw.get("attributes", {}) if isinstance(raw, dict) else {}
    attributes = {"enabled": _to_bool(src_attr.get("enabled"), True)}
    for k in ("created", "updated", "notBefore", "exp", "expires"):
        epoch = _to_epoch(src_attr.get(k))
        if epoch is not None:
            # azsecrets uses keys: created, updated, nbf, exp
            key = {"notBefore": "nbf", "expires": "exp"}.get(k, k)
            attributes[key] = epoch
    attributes.setdefault("recoveryLevel", "Purgeable")

    secret_id = raw.get("id") or f"https://{vault}.vault.azure.net/secrets/{name}"
    out = {"value": raw.get("value", ""), "id": secret_id, "attributes": attributes}
    if raw.get("contentType"):
        out["contentType"] = raw["contentType"]
    if raw.get("tags"):
        out["tags"] = raw["tags"]
    return out


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # quieter default logging
        log("%s - %s" % (self.address_string(), fmt % args))

    def _send_json(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    # ----- IMDS token endpoint (HTTP :8080) -----
    def _handle_imds(self, parsed):
        qs = parse_qs(parsed.query)
        resource = (qs.get("resource", ["https://vault.azure.net"])[0]).rstrip("/")
        client_id = qs.get("client_id", [""])[0]
        now = int(time.time())
        expires = now + 3600
        token = {
            "access_token": "miniblue-fake-token",
            "client_id": client_id,
            "expires_in": "3600",
            "expires_on": str(expires),
            "ext_expires_in": "3600",
            "not_before": str(now),
            "resource": resource,
            "token_type": "Bearer",
        }
        log(f"IMDS token issued resource={resource} client_id={client_id}")
        self._send_json(200, token)

    # ----- Key Vault data plane (HTTPS :8443) -----
    def _vault_from_host(self):
        host = self.headers.get("Host", "")
        host = host.split(":")[0]
        # {vault}.vault.azure.net -> {vault}
        return host.split(".")[0] if host else ""

    def _handle_keyvault(self, parsed):
        # Expected paths:
        #   /secrets/{name}
        #   /secrets/{name}/{version}
        parts = [p for p in parsed.path.split("/") if p]
        if len(parts) < 2 or parts[0] != "secrets":
            self._send_json(404, {"error": {"code": "NotFound", "message": "unsupported path"}})
            return
        name = parts[1]
        vault = self._vault_from_host()
        if not vault:
            self._send_json(400, {"error": {"code": "BadRequest", "message": "missing vault host"}})
            return
        upstream = f"{MINIBLUE_KV_BASE}/keyvault/{vault}/secrets/{name}"
        try:
            req = urllib.request.Request(upstream, method="GET")
            with urllib.request.urlopen(req, timeout=10) as resp:
                raw = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            log(f"upstream HTTPError {e.code} for {upstream}")
            self._send_json(e.code, {"error": {"code": "NotFound", "message": f"miniblue {e.code}"}})
            return
        except Exception as e:  # noqa: BLE001
            log(f"upstream error for {upstream}: {e}")
            self._send_json(502, {"error": {"code": "BadGateway", "message": str(e)}})
            return
        out = normalise_secret(raw, vault, name)
        log(f"KV GET vault={vault} secret={name} -> ok")
        self._send_json(200, out)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path.startswith("/metadata/"):
            self._handle_imds(parsed)
        elif parsed.path.startswith("/secrets/"):
            self._handle_keyvault(parsed)
        elif parsed.path in ("/healthz", "/"):
            self._send_json(200, {"status": "ok"})
        else:
            self._send_json(404, {"error": {"code": "NotFound", "message": "unknown path"}})


def serve_http():
    httpd = ThreadingHTTPServer(("0.0.0.0", HTTP_PORT), Handler)
    log(f"IMDS/HTTP listener on :{HTTP_PORT} (forwarding KV to {MINIBLUE_KV_BASE})")
    httpd.serve_forever()


def serve_https():
    httpd = ThreadingHTTPServer(("0.0.0.0", HTTPS_PORT), Handler)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(certfile=TLS_CERT_FILE, keyfile=TLS_KEY_FILE)
    httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
    log(f"KeyVault/HTTPS listener on :{HTTPS_PORT}")
    httpd.serve_forever()


def _wait_for_certs(timeout=60, interval=2):
    """Block until the TLS cert/key are present, else fail-fast for a pod restart.

    The TLS secret is mounted asynchronously; if the container starts before the
    files appear, load_cert_chain() raises FileNotFoundError. Waiting here (and
    exiting non-zero on timeout) lets the kubelet restart us instead of leaving a
    half-dead process serving only HTTP.
    """
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.exists(TLS_CERT_FILE) and os.path.exists(TLS_KEY_FILE):
            return
        log(f"waiting for TLS cert/key ({TLS_CERT_FILE}, {TLS_KEY_FILE})...")
        time.sleep(interval)
    log(f"FATAL: TLS cert/key not present after {timeout}s — exiting for restart")
    sys.exit(1)


def main():
    _wait_for_certs()
    # IMDS/HTTP runs in the background; KeyVault/HTTPS runs in the FOREGROUND so any
    # listener failure crashes the process (exit non-zero) and the kubelet restarts
    # the pod — never a "ready but :443 dead" state.
    threading.Thread(target=serve_http, daemon=True).start()
    log(f"miniblue-kv-proxy ready (kv_base={MINIBLUE_KV_BASE})")
    try:
        serve_https()
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == "__main__":
    main()
