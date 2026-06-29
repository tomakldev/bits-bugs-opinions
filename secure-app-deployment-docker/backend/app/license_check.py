"""Startup license validation.

Calls the vendor's license server before the app accepts traffic.
If the license is invalid or the server is unreachable, the process exits.
"""
import hashlib
import os
import sys

import httpx

_LICENSE_KEY = os.environ.get("LICENSE_KEY", "")
_LICENSE_SERVER = os.environ.get(
    "LICENSE_SERVER_URL", "https://license.yourdomain.com"
)


def _machine_fingerprint() -> str:
    """Stable per-host identifier for the license server to track deployments."""
    try:
        with open("/etc/machine-id") as f:
            node = f.read().strip()
    except OSError:
        import platform
        node = platform.node()
    return hashlib.sha256(node.encode()).hexdigest()[:24]


def verify_license_or_exit() -> None:
    """Validate the license key against the vendor's server.

    Exits the process on any failure — invalid key, unreachable server,
    or unexpected HTTP status. The app does not start without a valid license.
    """
    if not _LICENSE_KEY:
        print(
            "FATAL: LICENSE_KEY environment variable is not set.",
            file=sys.stderr,
        )
        sys.exit(1)

    try:
        response = httpx.post(
            f"{_LICENSE_SERVER}/api/v1/validate",
            json={
                "key": _LICENSE_KEY,
                "machine_id": _machine_fingerprint(),
            },
            timeout=15.0,
        )
    except httpx.ConnectError:
        print(
            "FATAL: Cannot connect to license server. "
            f"Check network access to {_LICENSE_SERVER}.",
            file=sys.stderr,
        )
        sys.exit(1)
    except httpx.TimeoutException:
        print("FATAL: License server timed out.", file=sys.stderr)
        sys.exit(1)

    if response.status_code != 200:
        print(
            f"FATAL: License server returned HTTP {response.status_code}.",
            file=sys.stderr,
        )
        sys.exit(1)

    data = response.json()
    if not data.get("valid"):
        reason = data.get("reason", "unknown")
        print(f"FATAL: License invalid — {reason}", file=sys.stderr)
        sys.exit(1)

    expires = data.get("expires_at", "never")
    print(f"License OK. Expires: {expires}")
